-- 057_reject_nric_in_messages.sql
-- Close the PDPA free-text gap: notes already reject NRIC/FIN (migration 011)
-- but parent/admin messages did not. A linked parent (or any writer who can
-- insert a message row) could persist a national identifier in subject/body.
--
-- 1. Table trigger so every write path is covered (admin insert + RPCs).
-- 2. send_parent_message rejects before insert for a stable error.

CREATE OR REPLACE FUNCTION public.reject_nric_in_messages()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(NEW.subject, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M'
       OR COALESCE(NEW.body, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'Message appears to contain an NRIC/FIN.'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reject_nric_in_messages()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_reject_nric_messages ON public.messages;
CREATE TRIGGER trg_reject_nric_messages
    BEFORE INSERT OR UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.reject_nric_in_messages();

CREATE OR REPLACE FUNCTION public.send_parent_message(
    p_student_id UUID,
    p_subject TEXT,
    p_body TEXT
)
RETURNS TABLE (
    id UUID,
    student_id UUID,
    subject TEXT,
    body TEXT,
    sent_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    is_from_parent BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_recent BIGINT;
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(BTRIM(p_body), '') IS NULL
       OR char_length(BTRIM(p_body)) > 10000
       OR (p_subject IS NOT NULL AND (
            NULLIF(BTRIM(p_subject), '') IS NULL
            OR char_length(BTRIM(p_subject)) > 200
       )) THEN
        RAISE EXCEPTION 'invalid message' USING ERRCODE = '23514';
    END IF;
    IF COALESCE(p_subject, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M'
       OR COALESCE(p_body, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'Message appears to contain an NRIC/FIN.'
            USING ERRCODE = '23514';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 3));
    DELETE FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'parent_message'
      AND created_at < NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'parent_message'
      AND created_at >= NOW() - INTERVAL '1 hour';
    IF v_recent >= 30 THEN
        RAISE EXCEPTION 'parent message limit reached'
            USING ERRCODE = '54000';
    END IF;
    INSERT INTO rate_limit_events (actor_id, action)
    VALUES (auth.uid(), 'parent_message');

    RETURN QUERY
    WITH inserted AS (
        INSERT INTO messages (
            sender_id, recipient_id, student_id, subject, body, read_at
        ) VALUES (
            auth.uid(), NULL, p_student_id, NULLIF(BTRIM(p_subject), ''),
            BTRIM(p_body), NULL
        )
        RETURNING *
    )
    SELECT i.id, i.student_id, i.subject, i.body, i.sent_at, i.read_at,
           TRUE
    FROM inserted i;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_parent_message(UUID, TEXT, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_parent_message(UUID, TEXT, TEXT)
    TO authenticated, service_role;

DO $$
DECLARE
    v_fn TEXT;
BEGIN
    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.messages'::REGCLASS
          AND tgname = 'trg_reject_nric_messages'
          AND tgenabled IN ('O', 'A')
    ), 'messages NRIC trigger missing or disabled';

    v_fn := LOWER(pg_get_functiondef(
        'public.send_parent_message(uuid,text,text)'::REGPROCEDURE
    ));
    ASSERT POSITION('nric/fin' IN v_fn) > 0,
           'send_parent_message lost the NRIC/FIN guard';
    ASSERT POSITION('security definer' IN v_fn) > 0,
           'send_parent_message must stay SECURITY DEFINER';
END;
$$;

NOTIFY pgrst, 'reload schema';

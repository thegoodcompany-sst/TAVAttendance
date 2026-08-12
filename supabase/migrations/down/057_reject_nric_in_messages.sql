-- Reverse of 057_reject_nric_in_messages.sql.
-- Restores the 038 send_parent_message body and drops the messages NRIC trigger.

DROP TRIGGER IF EXISTS trg_reject_nric_messages ON public.messages;
DROP FUNCTION IF EXISTS public.reject_nric_in_messages();

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

NOTIFY pgrst, 'reload schema';

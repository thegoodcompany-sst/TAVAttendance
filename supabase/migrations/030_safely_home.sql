-- 030_safely_home.sql
--
-- PROD-02 "safely home" write-back: a linked parent confirms their child got
-- home after a dismissal. dismissals.safely_home_at existed since 001 but
-- nothing wrote it. Two pieces, both dark until the push_notifications flag
-- flips and the Vault secret exists:
--
-- 1. mark_safely_home(p_dismissal_id) — SECURITY DEFINER RPC letting a parent
--    set safely_home_at on their own child's dismissal, once (non-null →
--    immutable). Parents have SELECT on dismissals (011) but no UPDATE policy;
--    a row-level UPDATE policy can't restrict to one column, so the RPC is the
--    tight write path.
-- 2. trg_notify_parent_dismissal — mirrors 021's attendance trigger: on
--    dismissal insert, POST to the notify-parent edge function via pg_net.
--    Triple-inert like 021 (Vault secret → flag → sender credentials).

CREATE OR REPLACE FUNCTION mark_safely_home(p_dismissal_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent() THEN RAISE EXCEPTION 'not authorized'; END IF;

    UPDATE dismissals
    SET safely_home_at = NOW(),
        confirmed_by   = auth.uid()
    WHERE id = p_dismissal_id
      AND safely_home_at IS NULL
      AND parent_owns_student(student_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'dismissal not found, already confirmed, or not your child';
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION mark_safely_home(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mark_safely_home(UUID) TO authenticated;

-- Notify parents when their child is dismissed (same inert-by-default pattern
-- as notify_parent_on_attendance, migration 021).
CREATE OR REPLACE FUNCTION notify_parent_on_dismissal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_key TEXT;
BEGIN
    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'notify_parent_service_key';

    IF v_key IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM net.http_post(
        url     := 'https://zgikcbsxzjgbigywxbbj.supabase.co/functions/v1/notify-parent',
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
            'student_id',   NEW.student_id,
            'status',       'dismissed',
            'session_id',   NEW.session_id,
            'dismissal_id', NEW.id
        )
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Notifications are best-effort; never fail the dismissal write.
    RAISE WARNING 'notify_parent_on_dismissal: %', SQLERRM;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_parent_on_dismissal() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_parent_dismissal ON dismissals;
CREATE TRIGGER trg_notify_parent_dismissal
    AFTER INSERT ON dismissals
    FOR EACH ROW
    EXECUTE FUNCTION notify_parent_on_dismissal();

NOTIFY pgrst, 'reload schema';

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'mark_safely_home')),
           'mark_safely_home missing after 030';
    ASSERT (SELECT NOT has_function_privilege('anon', 'mark_safely_home(uuid)', 'EXECUTE')),
           'anon can execute mark_safely_home after 030';
    ASSERT (SELECT has_function_privilege('authenticated', 'mark_safely_home(uuid)', 'EXECUTE')),
           'authenticated cannot execute mark_safely_home after 030';
    ASSERT (SELECT EXISTS (SELECT FROM pg_trigger
            WHERE tgname = 'trg_notify_parent_dismissal'
              AND tgrelid = 'dismissals'::regclass)),
           'trg_notify_parent_dismissal missing after 030';
    ASSERT (SELECT NOT has_function_privilege('authenticated', 'notify_parent_on_dismissal()', 'EXECUTE')),
           'authenticated can execute notify_parent_on_dismissal after 030';
END $$;

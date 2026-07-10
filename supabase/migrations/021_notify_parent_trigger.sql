-- 021_notify_parent_trigger.sql
--
-- PROD-02: invoke the notify-parent edge function (via pg_net) whenever an
-- attendance record lands as late/absent. Triple-inert by design:
--   1. the function no-ops unless the Vault secret 'notify_parent_service_key'
--      exists (seeded by a human — HUMANS.md §17; never in git),
--   2. the edge function no-ops unless the push_notifications flag is ON,
--   3. the edge function no-ops unless APNs secrets are configured.
-- Any error here is swallowed: a broken notification path must never block
-- marking attendance.

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION notify_parent_on_attendance()
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
            'student_id', NEW.student_id,
            'status',     NEW.status,
            'session_id', NEW.session_id
        )
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Notifications are best-effort; never fail the attendance write.
    RAISE WARNING 'notify_parent_on_attendance: %', SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_parent ON attendance_records;
CREATE TRIGGER trg_notify_parent
    AFTER INSERT OR UPDATE OF status ON attendance_records
    FOR EACH ROW
    WHEN (NEW.status IN ('late', 'absent'))
    EXECUTE FUNCTION notify_parent_on_attendance();

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (SELECT FROM pg_trigger
            WHERE tgname = 'trg_notify_parent'
              AND tgrelid = 'attendance_records'::regclass)),
           'trg_notify_parent missing after 021';
    ASSERT (SELECT EXISTS (SELECT FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'notify_parent_on_attendance')),
           'notify_parent_on_attendance missing after 021';
END $$;

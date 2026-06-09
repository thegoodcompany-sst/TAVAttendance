-- ============================================================
-- Security hardening — 2026-06-10
-- Addresses Supabase security advisor findings:
--   1. [ERROR] attendance_summary still ran with owner (postgres)
--      privileges on the live DB — 007 was written but the live view
--      had reloptions = NULL, so RLS on the underlying tables was
--      bypassed: any authenticated tutor/parent could read every
--      student's attendance summary. ALTER (idempotent) re-asserts it.
--   2. [WARN] Mutable search_path on all public functions — pin it so
--      SECURITY DEFINER functions can't be hijacked via search_path.
--   3. [WARN] Trigger functions were RPC-exposed to anon/authenticated.
--   4. [WARN] RLS helper functions were executable by anon.
-- ============================================================

-- ── 1. attendance_summary: run with invoker rights ───────────
ALTER VIEW public.attendance_summary SET (security_invoker = on);

-- ── 2. Pin search_path on every public function ──────────────
ALTER FUNCTION public.get_session_roster(uuid)   SET search_path = public;
ALTER FUNCTION public.get_my_role()              SET search_path = public;
ALTER FUNCTION public.is_admin()                 SET search_path = public;
ALTER FUNCTION public.is_tutor()                 SET search_path = public;
ALTER FUNCTION public.is_parent()                SET search_path = public;
ALTER FUNCTION public.tutor_owns_class(uuid)     SET search_path = public;
ALTER FUNCTION public.parent_owns_student(uuid)  SET search_path = public;
ALTER FUNCTION public.set_updated_at()           SET search_path = public;
ALTER FUNCTION public.sync_attendance(jsonb)     SET search_path = public;
ALTER FUNCTION public.audit_trigger_func()       SET search_path = public;
ALTER FUNCTION public.handle_new_user()          SET search_path = public;

-- ── 3. Trigger functions must not be callable via /rest/v1/rpc ──
-- (Triggers only check EXECUTE at CREATE TRIGGER time, so existing
-- triggers — including auth.users → handle_new_user — keep firing.)
REVOKE EXECUTE ON FUNCTION public.audit_trigger_func() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user()    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_updated_at()     FROM PUBLIC, anon, authenticated;

-- ── 4. App/RLS-helper functions: authenticated + service_role only ──
REVOKE EXECUTE ON FUNCTION public.get_my_role()             FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_admin()                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_tutor()                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_parent()               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.tutor_owns_class(uuid)    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.parent_owns_student(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_session_roster(uuid)  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.sync_attendance(jsonb)    FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_my_role()             TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin()                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_tutor()                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_parent()               TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tutor_owns_class(uuid)    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.parent_owns_student(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_session_roster(uuid)  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_attendance(jsonb)    TO authenticated, service_role;

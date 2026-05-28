-- ============================================================
-- Security fixes — applied 2026-05-26
-- ============================================================

-- ── [CRITICAL] Prevent self-service privilege escalation ─────
-- The previous "profiles: user can update own" policy allowed
-- any authenticated user to UPDATE profiles.role to "admin"
-- because WITH CHECK only verified id = auth.uid().
-- Fix: role column must not change unless the current user is
-- already an admin (handled by the "admin can update any" policy).

DROP POLICY IF EXISTS "profiles: user can update own" ON profiles;

CREATE POLICY "profiles: user can update own"
    ON profiles FOR UPDATE
    TO authenticated
    USING  (id = auth.uid())
    WITH CHECK (
        id = auth.uid()
        -- role must stay the same as the currently stored value
        AND role = (SELECT role FROM profiles WHERE id = auth.uid())
    );


-- ── [HIGH] Restrict profile reads — no cross-tenant PII leak ─
-- The previous policy exposed every profile row (full_name,
-- phone, role) to all authenticated users.
-- Fix: each user can only read their own row; admins see all.

DROP POLICY IF EXISTS "profiles: any auth user can read" ON profiles;

CREATE POLICY "profiles: read own or admin"
    ON profiles FOR SELECT
    TO authenticated
    USING (id = auth.uid() OR is_admin());

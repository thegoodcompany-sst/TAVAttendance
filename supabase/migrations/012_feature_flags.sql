-- ============================================================
-- 012 — Feature flags
-- ============================================================
-- A single source of truth for gating in-progress features across
-- iOS, Android and web. Flags ship OFF; an admin flips `enabled` when
-- a feature is ready. The matching code on every platform reads these
-- and hides the feature until the flag is true.
--
-- Down migration: 012_feature_flags.down.sql

CREATE TABLE IF NOT EXISTS feature_flags (
    key         TEXT PRIMARY KEY,
    enabled     BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Helper usable from policies / triggers / app queries.
-- SECURITY DEFINER + pinned search_path (per 009_security_hardening.sql convention)
-- so it reads the table regardless of the caller's RLS context.
CREATE OR REPLACE FUNCTION is_feature_enabled(p_key TEXT)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public AS $$
    SELECT COALESCE((SELECT enabled FROM feature_flags WHERE key = p_key), FALSE)
$$;

-- ── RLS: everyone authenticated may read; only admins may change ──
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "feature_flags: read for authenticated" ON feature_flags;
CREATE POLICY "feature_flags: read for authenticated"
    ON feature_flags FOR SELECT
    TO authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "feature_flags: admin writes" ON feature_flags;
CREATE POLICY "feature_flags: admin writes"
    ON feature_flags FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

-- ── Seed: all OFF ────────────────────────────────────────────
INSERT INTO feature_flags (key, enabled, description) VALUES
    ('parent_portal',      FALSE, 'Parent-facing attendance view (PROD-01)'),
    ('push_notifications', FALSE, 'Push notifications to parents on late/absent (PROD-02)'),
    ('student_photos',     FALSE, 'Student avatar photos on kiosk/roster cards (PROD-04)')
ON CONFLICT (key) DO NOTHING;

GRANT SELECT ON feature_flags TO authenticated;

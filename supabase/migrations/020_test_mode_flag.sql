-- 020_test_mode_flag.sql
--
-- Demo/test mode flag. When ON: the iOS kiosk shows all active classes
-- regardless of weekday (bypasses the day-aware filter from 015) and the web
-- analytics includes non-tuition days (Mon/Thu). Seeded ON deliberately —
-- demo day 2026-07-11 is a Saturday; HUMANS.md §37 flips it OFF and deletes
-- the demo-day data afterwards.

INSERT INTO feature_flags (key, enabled, description) VALUES
    ('test_mode', TRUE,
     'Demo/test mode: kiosk shows all active classes regardless of weekday; web analytics includes non-Mon/Thu days. Flip OFF after demo/testing.')
ON CONFLICT (key) DO NOTHING;

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (SELECT FROM feature_flags WHERE key = 'test_mode')),
           'test_mode flag missing after 020';
END $$;

-- 026_feature_flags_notes_qr_awards.sql
--
-- Flag rows for the next feature batch, all shipped OFF (change-control rule).
-- No schema changes: sessions.notes (001) and awards (014) already exist.
--   session_notes — tutors write a free-text note per session (roster screen).
--   qr_sign_in    — kiosk QR-scan entry point that reuses the tap-to-sign path.
--   awards        — admin web page computing award candidates from
--                   attendance_summary and recording rows in awards.

INSERT INTO feature_flags (key, enabled, description) VALUES
    ('session_notes', FALSE,
     'Tutor session notes: edit sessions.notes from the roster screen (iOS/Android) and session detail (web).'),
    ('qr_sign_in', FALSE,
     'Kiosk QR sign-in: scan a student QR code as an alternative to tapping the card.'),
    ('awards', FALSE,
     'Admin awards page: compute attendance/punctuality award candidates and record them in the awards table.')
ON CONFLICT (key) DO NOTHING;

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM feature_flags
            WHERE key IN ('session_notes', 'qr_sign_in', 'awards')) = 3,
           'flag rows missing after 026';
END $$;

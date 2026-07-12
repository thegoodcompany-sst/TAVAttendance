-- down/026_feature_flags_notes_qr_awards.sql — reverse of 026.

DELETE FROM feature_flags WHERE key IN ('session_notes', 'qr_sign_in', 'awards');

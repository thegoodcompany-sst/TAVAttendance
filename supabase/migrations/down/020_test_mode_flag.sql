-- down/020_test_mode_flag.sql — reverse of 020.

DELETE FROM feature_flags WHERE key = 'test_mode';

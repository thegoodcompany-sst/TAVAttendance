-- Down migration for 012_feature_flags.sql
DROP FUNCTION IF EXISTS is_feature_enabled(TEXT);
DROP TABLE IF EXISTS feature_flags;

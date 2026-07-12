-- down/027_awards_unique.sql — reverse of 027.

ALTER TABLE awards DROP CONSTRAINT IF EXISTS awards_student_type_period_key;

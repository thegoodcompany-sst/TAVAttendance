-- ============================================================
-- 006_session_end.sql
-- Adds columns that were missing from the live DB but used by
-- the Swift app:
--   started_at   — set when tutor taps "Start Class"
--   sub_tutor_id — per-session substitute tutor (Sprint 2)
--   ended_at     — set when tutor ends the class; nil = in progress
-- ============================================================

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS started_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sub_tutor_id UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS ended_at     TIMESTAMPTZ;

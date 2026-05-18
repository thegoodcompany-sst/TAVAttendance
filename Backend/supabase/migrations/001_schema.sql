-- ============================================================
-- TAVA Attendance Platform — Initial Schema
-- Phase 1: Attendance (fully implemented)
-- Phase 2-3: Tables created, logic to be added later
-- ============================================================

-- ── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ── Profiles ─────────────────────────────────────────────────
-- Extends Supabase auth.users. One row per user account.
CREATE TABLE profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name   TEXT NOT NULL,
    role        TEXT NOT NULL CHECK (role IN ('admin', 'tutor', 'parent')),
    phone       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create a profile stub when a new auth user is invited.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
        COALESCE(NEW.raw_user_meta_data->>'role', 'tutor')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- ── Students ─────────────────────────────────────────────────
CREATE TABLE students (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       TEXT NOT NULL,
    date_of_birth   DATE,
    school          TEXT,
    year_of_study   TEXT,   -- e.g. "Sec 2", "JC1"
    notes           TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES auth.users(id)
);


-- ── Parent ↔ Student Links ────────────────────────────────────
CREATE TABLE parent_student_links (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    relationship    TEXT NOT NULL DEFAULT 'parent',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (parent_id, student_id)
);


-- ── Classes ──────────────────────────────────────────────────
CREATE TABLE classes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT NOT NULL,   -- e.g. "Sec 2 Math Tues"
    subject             TEXT,
    level               TEXT,            -- e.g. "Sec 2"
    schedule_day        TEXT,            -- e.g. "Tuesday"
    schedule_time       TIME,
    duration_minutes    INT NOT NULL DEFAULT 90,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ── Class ↔ Tutor Assignments ─────────────────────────────────
CREATE TABLE class_tutor_assignments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    tutor_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assigned_from   DATE NOT NULL DEFAULT CURRENT_DATE,
    assigned_until  DATE,
    UNIQUE (class_id, tutor_id)
);


-- ── Enrollments ───────────────────────────────────────────────
CREATE TABLE enrollments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unenrolled_at   TIMESTAMPTZ,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (student_id, class_id)
);


-- ── Sessions ─────────────────────────────────────────────────
-- A session is a class on a specific calendar date.
-- Attendance is always tied to a session, never directly to a class.
CREATE TABLE sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    session_date    DATE NOT NULL,
    start_time      TIME,
    end_time        TIME,
    topic           TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID REFERENCES auth.users(id),
    UNIQUE (class_id, session_date)
);


-- ── Attendance Records ────────────────────────────────────────
CREATE TABLE attendance_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    student_id          UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    status              TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
    marked_by           UUID REFERENCES auth.users(id),
    marked_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes               TEXT,
    -- Idempotency key generated on-device; prevents double-insert on retry after offline sync.
    client_mutation_id  TEXT UNIQUE,
    UNIQUE (session_id, student_id)
);


-- ── Audit Log ─────────────────────────────────────────────────
-- Written only by triggers (SECURITY DEFINER). No app writes directly.
CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name  TEXT NOT NULL,
    record_id   UUID NOT NULL,
    action      TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data    JSONB,
    new_data    JSONB,
    changed_by  UUID REFERENCES auth.users(id),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX audit_log_table_record_idx ON audit_log (table_name, record_id);
CREATE INDEX audit_log_changed_at_idx   ON audit_log (changed_at DESC);


-- ═══════════════════════════════════════════════════════════════
-- PHASE 2 STUBS — tables only, no RLS / business logic yet
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE result_slips (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    exam_name       TEXT,
    exam_date       DATE,
    subject         TEXT,
    score           NUMERIC,
    max_score       NUMERIC,
    file_path       TEXT,   -- Supabase Storage object path
    uploaded_by     UUID REFERENCES auth.users(id),
    uploaded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    acknowledged_by UUID REFERENCES auth.users(id),
    acknowledged_at TIMESTAMPTZ
);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id       UUID REFERENCES auth.users(id),
    recipient_id    UUID REFERENCES auth.users(id),
    student_id      UUID REFERENCES students(id),
    subject         TEXT,
    body            TEXT NOT NULL,
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at         TIMESTAMPTZ
);

CREATE TABLE awards (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    award_type      TEXT,   -- 'attendance', 'punctuality', 'resilience'
    period          TEXT,   -- e.g. '2026-Q1'
    awarded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    awarded_by      UUID REFERENCES auth.users(id)
);


-- ═══════════════════════════════════════════════════════════════
-- PHASE 3 STUBS
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE dismissals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID REFERENCES sessions(id),
    student_id      UUID REFERENCES students(id),
    dismissed_at    TIMESTAMPTZ,
    dismissed_by    UUID REFERENCES auth.users(id),
    safely_home_at  TIMESTAMPTZ,
    confirmed_by    UUID REFERENCES auth.users(id)
);

CREATE TABLE food_polls (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT NOT NULL,
    event_name  TEXT,
    event_date  DATE,
    options     JSONB NOT NULL DEFAULT '[]',
    created_by  UUID REFERENCES auth.users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closes_at   TIMESTAMPTZ
);

CREATE TABLE food_poll_responses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id         UUID NOT NULL REFERENCES food_polls(id) ON DELETE CASCADE,
    student_id      UUID REFERENCES students(id),
    responded_by    UUID REFERENCES auth.users(id),
    selection       JSONB,
    responded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (poll_id, student_id)
);

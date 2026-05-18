# TAVA Attendance — Backend

Powered by [Supabase](https://supabase.com) (Postgres + Auth + Storage + Realtime).

---

## Project Structure

```
Backend/
├── supabase/
│   ├── config.toml                    Supabase local dev config
│   ├── seed.sql                       Dev seed data (local only)
│   └── migrations/
│       ├── 001_schema.sql             All tables (Phase 1 full, Phase 2/3 stubs)
│       ├── 002_rls.sql                Row Level Security policies
│       └── 003_functions_triggers.sql Audit log, helper functions, offline sync RPC
└── API.md                             iOS integration guide (Swift SDK examples)
```

---

## Prerequisites

```bash
brew install supabase/tap/supabase
```

---

## Local Development

### 1. Start local Supabase

```bash
cd Backend
supabase start
```

Supabase will print a local URL, anon key, and service role key. Use the local values in the iOS app during development.

### 2. Apply migrations

Migrations run automatically on `supabase start`. To re-apply manually:

```bash
supabase db reset
```

### 3. Load seed data

```bash
supabase db reset --seed
```

This creates three dev accounts:

| Role   | Email            | Password      |
|--------|------------------|---------------|
| Admin  | admin@tava.dev   | TAVAdev123!   |
| Tutor  | tutor@tava.dev   | TAVAdev123!   |
| Parent | parent@tava.dev  | TAVAdev123!   |

### 4. Open Supabase Studio

```
http://localhost:54323
```

Use the Table Editor and SQL Editor to inspect data during development.

---

## Deploying to Production

### 1. Create a Supabase project

- Go to [supabase.com/dashboard](https://supabase.com/dashboard) → New Project
- Choose the **Singapore (ap-southeast-1)** region (PDPA data residency)
- Free tier is sufficient for MVP

### 2. Link the project

```bash
supabase link --project-ref YOUR_PROJECT_REF
```

### 3. Push migrations

```bash
supabase db push
```

### 4. Configure Auth

In **Supabase Dashboard → Authentication → Settings**:
- Disable "Enable email signup" (invite-only)
- Enable "Email confirmations"
- Set Site URL to your admin web app URL (if building one)
- Add `tava-attendance://auth-callback` to Redirect URLs (for the iOS app)

### 5. Invite the first admin

In **Dashboard → Authentication → Users → Invite user**:
- Email: admin's email
- User metadata: `{"full_name": "Your Name", "role": "admin"}`

Subsequent users are invited by the admin from within the app (Phase 2).

---

## Security Notes

- **PDPA Compliance**: All data is stored in Singapore (ap-southeast-1). Supabase encrypts data at rest (AES-256) and in transit (TLS 1.3). Do not store NRIC or other PDPA-sensitive identifiers unless required.
- **Minor data**: Students are minors. Limit access to the minimum necessary. The `parent_student_links` table ensures parents see only their own children.
- **Anon key**: Safe to ship in the iOS app. It is a publishable key; RLS policies enforce all access control.
- **Service role key**: Never ship in the iOS app. Use only for admin scripts or server-side tooling.
- **Audit log**: Every write to `students`, `attendance_records`, `sessions`, and `enrollments` is logged automatically via database triggers. No application code required.

---

## Phase Roadmap

| Phase | Status | Tables Active |
|-------|--------|---------------|
| 1 — Attendance | **Complete** | profiles, students, classes, class_tutor_assignments, enrollments, sessions, attendance_records, audit_log |
| 2 — Results & Messaging | Schema only | result_slips, messages, awards |
| 3 — Safety & Logistics | Schema only | dismissals, food_polls, food_poll_responses |

Phase 2/3 tables exist but have admin-only RLS. Unlock them by adding proper policies and business logic in new migration files when ready.

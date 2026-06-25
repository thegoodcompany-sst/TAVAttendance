# Superadmin Feature-Flags Section — Design

**Date:** 2026-06-25
**Status:** Approved
**Surface:** `web/` (Next.js admin dashboard)

## Goal

Give a single superadmin (`edmund@thegoodcompanysg.dev`) a UI in the web dashboard
to view and toggle the rows in the `feature_flags` table. No such UI exists today —
flags can only be flipped via the Supabase dashboard / raw SQL.

## Constraints & decisions

- **Enforcement is app-layer only.** The page, the server action, and the sidebar
  link all check the caller's email. The database RLS write policy stays at
  `is_admin()` (migration 012) — it is **not** tightened. A determined non-superadmin
  admin could therefore still write to `feature_flags` via a raw API call; this is
  accepted because other admins are trusted teammates. No Supabase migration is touched.
- **Allowed email comes from an env var.** `SUPERADMIN_EMAIL`, defaulting to
  `edmund@thegoodcompanysg.dev`. Because it has a default, an unset env var does not
  block deploys; it just keeps the current intended gate.
- **The flag list is dynamic**, driven by the rows in `feature_flags`. Flags added
  later (including via migration) appear automatically with no code change.
- **Web has no automated test suite** (per project `CLAUDE.md`). Verification is
  `npm run build` + `npm run lint` plus manual checks.

## Components

### `web/lib/superadmin.ts` (new, server-only)
Single source of truth for the gate.
- `getSuperadminEmail(): string` — `process.env.SUPERADMIN_EMAIL ?? 'edmund@thegoodcompanysg.dev'`.
- `isSuperadmin(user: { email?: string | null } | null): boolean` — case-insensitive
  compare of `user?.email` to the configured email. Returns `false` for `null`/missing email.

### `web/app/(admin)/feature-flags/page.tsx` (new, server component)
- Lives inside the existing admin layout, which already redirects non-admins.
- Fetches the current user; if `!isSuperadmin(user)` → `notFound()` (renders a 404 so the
  route's existence is not confirmed to ordinary admins).
- Reads `SELECT key, enabled, description, updated_at FROM feature_flags ORDER BY key`
  via the RLS-scoped server client.
- Renders a page header and `<FlagsList flags={...} />`.

### `web/app/(admin)/feature-flags/flags-list.tsx` (new, client component)
- Receives the flags array.
- One row per flag: humanized label derived from `key` (e.g. `parent_portal` → "Parent portal"),
  the `description`, a relative "updated …" timestamp, and a `<Switch>`.
- Toggling: optimistic local state update → calls `setFeatureFlag(key, next)`. On error,
  reverts the toggle and shows the error message inline (styled like the `invite-form` error).
- Disables the switch while the action is in flight.

### `web/app/actions/feature-flags.ts` (new, server action)
- `setFeatureFlag(key: string, enabled: boolean): Promise<{ error: string | null }>`.
- Re-checks server-side: authenticated **and** `isSuperadmin(user)` — never trusts the client.
  Returns an error string if not.
- Validates `key`: it must already exist in `feature_flags` (reject arbitrary keys), mirroring
  the runtime role-guard pattern in `invite.ts`.
- `UPDATE feature_flags SET enabled = $enabled, updated_at = now() WHERE key = $key`
  via the RLS-scoped `createClient()` (passes the existing `is_admin()` write policy).
- `revalidatePath('/feature-flags')` on success.

### `web/components/ui/switch.tsx` (new)
- Minimal shadcn-style toggle switch (none exists in `components/ui/` yet). Accessible
  (`role="switch"`, `aria-checked`), keyboard-operable, matching the existing Tailwind/brand tokens.
- Used only by the feature-flags list for now.

### Sidebar / layout changes
- `web/app/(admin)/layout.tsx`: compute `isSuperadmin(user)` and pass it as a prop to `<Sidebar>`.
- `web/components/dashboard/sidebar.tsx`: render an extra "Feature Flags" nav item
  (icon e.g. `Flag` from lucide) **only** when `isSuperadmin` is true. Non-superadmins
  never see the link.
- Mobile top-nav in `layout.tsx`: same conditional item, kept consistent with the sidebar.

### Env documentation
- `web/.env.local.example`: add `SUPERADMIN_EMAIL=edmund@thegoodcompanysg.dev` with a comment
  noting it gates the feature-flags admin section and defaults to that value if unset.

## Data flow

1. Superadmin opens `/feature-flags`.
2. Page reads all flag rows (RLS allows any authenticated read).
3. User flips a switch → optimistic UI + `setFeatureFlag(key, enabled)`.
4. Action re-verifies superadmin, validates the key, `UPDATE`s under `is_admin()` RLS.
5. `revalidatePath('/feature-flags')` → server re-renders with persisted values.
6. On failure the client reverts the optimistic toggle and shows the inline error.

## Error handling

- Action returns `{ error: string | null }` (same shape as `invite.ts`).
- Not authenticated → `"Not authenticated."`; not superadmin → `"Not authorized."`;
  unknown key → `"Unknown feature flag."`; DB error → the Postgres error message.
- Client reverts optimistic state and renders the message inline.

## Out of scope

- No changes to how iOS/Android/web *read* flags (`getFeatureFlags()` etc. unchanged).
- No Supabase migration / RLS change.
- No audit log of who toggled what (the `updated_at` column is refreshed, but no actor is recorded).
- No new flags are created from the UI — only existing rows are toggled.

## Verification

- `cd web && npm run build` — type-checks and compiles.
- `cd web && npm run lint`.
- Manual, signed in as `edmund@thegoodcompanysg.dev`: nav link visible; page lists the 3 seeded
  flags; toggling one persists across reload.
- Manual, signed in as a different admin: no nav link; visiting `/feature-flags` returns 404.

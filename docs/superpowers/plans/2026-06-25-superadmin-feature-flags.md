# Superadmin Feature-Flags Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a web admin page, visible only to `edmund@thegoodcompanysg.dev`, that lists and toggles rows in the `feature_flags` table.

**Architecture:** A new server-only `isSuperadmin` gate (env-driven) protects a new `/feature-flags` route inside the existing admin layout; a client list component flips switches via a `setFeatureFlag` server action that re-verifies the gate and updates the table under its existing `is_admin()` RLS write policy. The sidebar link renders only for the superadmin.

**Tech Stack:** Next.js 16.2.6 (App Router, RSC, server actions), `@supabase/ssr`, Tailwind, lucide-react.

## Global Constraints

- **Web has NO automated test suite.** Per project `CLAUDE.md`, verification = `npm run lint` + `npm run build` + manual checks. Do NOT add a test runner. "Test" steps below mean lint/build/manual.
- **Package manager:** use `npm` (repo has `package-lock.json`), run from `web/`.
- **Allowed email:** `process.env.SUPERADMIN_EMAIL`, default `edmund@thegoodcompanysg.dev` (compare case-insensitively, trimmed).
- **Enforcement is app-layer only.** Do NOT add or edit any Supabase migration / RLS policy.
- **Do NOT import `server-only`** — it is not a dependency. Keep server-only modules out of client imports by convention.
- **Imports:** `revalidatePath` from `next/cache`; `notFound` from `next/navigation`; `createClient` from `@/lib/supabase/server`; `cn` from `@/lib/utils`.
- **Server action shape:** `Promise<{ error: string | null }>`, mirroring `app/actions/invite.ts`.

---

### Task 1: Superadmin gate helper + env documentation

**Files:**
- Create: `web/lib/superadmin.ts`
- Modify: `web/.env.local.example`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `getSuperadminEmail(): string` — lowercased, trimmed configured email.
  - `isSuperadmin(user: { email?: string | null } | null): boolean`.

- [ ] **Step 1: Create the gate helper**

Create `web/lib/superadmin.ts`:

```ts
// Server-only gate for the feature-flags admin section. Enforcement is
// app-layer only (see docs/superpowers/specs/2026-06-25-superadmin-feature-flags-design.md):
// the DB RLS write policy stays at is_admin(). Imported only by server
// components and server actions — never by a client component.

const DEFAULT_SUPERADMIN_EMAIL = 'edmund@thegoodcompanysg.dev'

export function getSuperadminEmail(): string {
  return (process.env.SUPERADMIN_EMAIL ?? DEFAULT_SUPERADMIN_EMAIL).trim().toLowerCase()
}

export function isSuperadmin(user: { email?: string | null } | null): boolean {
  const email = user?.email?.trim().toLowerCase()
  return !!email && email === getSuperadminEmail()
}
```

- [ ] **Step 2: Document the env var**

Append to `web/.env.local.example` (it currently has only the two `NEXT_PUBLIC_SUPABASE_*` lines):

```bash

# Email allowed to access the /feature-flags admin section.
# Defaults to edmund@thegoodcompanysg.dev if unset.
SUPERADMIN_EMAIL=edmund@thegoodcompanysg.dev
```

- [ ] **Step 3: Lint the new file**

Run: `cd web && npx eslint lib/superadmin.ts`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add web/lib/superadmin.ts web/.env.local.example
git commit -m "feat(web): add superadmin gate helper + env var"
```

---

### Task 2: Switch UI component

**Files:**
- Create: `web/components/ui/switch.tsx`

**Interfaces:**
- Consumes: `cn` from `@/lib/utils`.
- Produces: `Switch` component with props
  `{ checked: boolean; onCheckedChange: (checked: boolean) => void; disabled?: boolean; id?: string; 'aria-label'?: string }`.

- [ ] **Step 1: Create the Switch component**

Create `web/components/ui/switch.tsx`:

```tsx
'use client'

import { cn } from '@/lib/utils'

interface SwitchProps {
  checked: boolean
  onCheckedChange: (checked: boolean) => void
  disabled?: boolean
  id?: string
  'aria-label'?: string
}

export function Switch({ checked, onCheckedChange, disabled, id, ...rest }: SwitchProps) {
  return (
    <button
      type="button"
      role="switch"
      id={id}
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onCheckedChange(!checked)}
      className={cn(
        'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer items-center rounded-full transition-colors',
        'focus:outline-none focus-visible:ring-2 focus-visible:ring-brand/30',
        'disabled:cursor-not-allowed disabled:opacity-50',
        checked ? 'bg-brand' : 'bg-muted'
      )}
      {...rest}
    >
      <span
        className={cn(
          'inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform',
          checked ? 'translate-x-5' : 'translate-x-0.5'
        )}
      />
    </button>
  )
}
```

- [ ] **Step 2: Lint the new file**

Run: `cd web && npx eslint components/ui/switch.tsx`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add web/components/ui/switch.tsx
git commit -m "feat(web): add Switch UI component"
```

---

### Task 3: setFeatureFlag server action

**Files:**
- Create: `web/app/actions/feature-flags.ts`

**Interfaces:**
- Consumes: `isSuperadmin` (Task 1); `createClient` from `@/lib/supabase/server`.
- Produces: `setFeatureFlag(key: string, enabled: boolean): Promise<{ error: string | null }>`.

- [ ] **Step 1: Create the server action**

Create `web/app/actions/feature-flags.ts`:

```ts
'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'

export async function setFeatureFlag(
  key: string,
  enabled: boolean
): Promise<{ error: string | null }> {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }
  if (!isSuperadmin(user)) return { error: 'Not authorized.' }

  // Validate the key exists before writing — types are stripped at runtime so a
  // raw POST could supply anything. Mirrors the runtime guard in invite.ts.
  const { data: existing, error: lookupError } = await supabase
    .from('feature_flags')
    .select('key')
    .eq('key', key)
    .maybeSingle()
  if (lookupError) return { error: lookupError.message }
  if (!existing) return { error: 'Unknown feature flag.' }

  const { error } = await supabase
    .from('feature_flags')
    .update({ enabled, updated_at: new Date().toISOString() })
    .eq('key', key)
  if (error) return { error: error.message }

  revalidatePath('/feature-flags')
  return { error: null }
}
```

- [ ] **Step 2: Lint the new file**

Run: `cd web && npx eslint app/actions/feature-flags.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add web/app/actions/feature-flags.ts
git commit -m "feat(web): add setFeatureFlag server action"
```

---

### Task 4: Feature-flags page + client list

**Files:**
- Create: `web/app/(admin)/feature-flags/page.tsx`
- Create: `web/app/(admin)/feature-flags/flags-list.tsx`

**Interfaces:**
- Consumes: `isSuperadmin` (Task 1); `Switch` (Task 2); `setFeatureFlag` (Task 3); `createClient`; `notFound`.
- Produces: a `FlagRow` shape `{ key: string; enabled: boolean; description: string | null; updated_at: string }` shared between the two files (define it in `flags-list.tsx`, import into `page.tsx`).

- [ ] **Step 1: Create the client list component**

Create `web/app/(admin)/feature-flags/flags-list.tsx`:

```tsx
'use client'

import { useState } from 'react'
import { Switch } from '@/components/ui/switch'
import { setFeatureFlag } from '@/app/actions/feature-flags'

export interface FlagRow {
  key: string
  enabled: boolean
  description: string | null
  updated_at: string
}

function humanize(key: string): string {
  const s = key.replace(/_/g, ' ')
  return s.charAt(0).toUpperCase() + s.slice(1)
}

export function FlagsList({ flags }: { flags: FlagRow[] }) {
  return (
    <ul className="divide-y divide-border">
      {flags.map(flag => (
        <FlagItem key={flag.key} flag={flag} />
      ))}
    </ul>
  )
}

function FlagItem({ flag }: { flag: FlagRow }) {
  const [enabled, setEnabled] = useState(flag.enabled)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const updatedAt = new Date(flag.updated_at).toLocaleDateString('en-SG', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })

  async function toggle(next: boolean) {
    setError(null)
    setEnabled(next) // optimistic
    setPending(true)
    const { error: actionError } = await setFeatureFlag(flag.key, next)
    setPending(false)
    if (actionError) {
      setEnabled(!next) // revert
      setError(actionError)
    }
  }

  return (
    <li className="flex items-start gap-4 px-6 py-4">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-foreground">{humanize(flag.key)}</p>
          <code className="text-[11px] text-muted-foreground bg-muted px-1.5 py-0.5 rounded">
            {flag.key}
          </code>
        </div>
        {flag.description && (
          <p className="text-xs text-muted-foreground mt-0.5 leading-snug">{flag.description}</p>
        )}
        <p className="text-[11px] text-muted-foreground mt-1">Updated {updatedAt}</p>
        {error && (
          <p className="text-xs text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-2.5 py-1.5 mt-2">
            {error}
          </p>
        )}
      </div>
      <div className="pt-0.5">
        <Switch
          checked={enabled}
          onCheckedChange={toggle}
          disabled={pending}
          aria-label={`Toggle ${humanize(flag.key)}`}
        />
      </div>
    </li>
  )
}
```

- [ ] **Step 2: Create the page (server component)**

Create `web/app/(admin)/feature-flags/page.tsx`:

```tsx
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'
import { FlagsList, type FlagRow } from './flags-list'

export default async function FeatureFlagsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  // Hide the route's existence from ordinary admins (the (admin) layout already
  // guarantees user is a signed-in admin).
  if (!isSuperadmin(user)) notFound()

  const { data } = await supabase
    .from('feature_flags')
    .select('key, enabled, description, updated_at')
    .order('key', { ascending: true })

  const flags = (data ?? []) as FlagRow[]

  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <div>
        <h1 className="text-2xl font-semibold text-foreground tracking-tight">Feature flags</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Toggle in-progress features across iOS, Android, and web. Changes take effect on next load.
        </p>
      </div>

      <div className="bg-white rounded-2xl border border-border shadow-sm overflow-hidden">
        <div className="px-6 py-4 border-b border-border flex items-center justify-between">
          <h2 className="text-sm font-semibold text-foreground">Flags</h2>
          <span className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded-full">
            {flags.length}
          </span>
        </div>
        {flags.length === 0 ? (
          <div className="px-6 py-10 text-center text-sm text-muted-foreground">
            No feature flags defined.
          </div>
        ) : (
          <FlagsList flags={flags} />
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Build to type-check the route**

Run: `cd web && npm run build`
Expected: build succeeds; no type errors for the new files.

- [ ] **Step 4: Commit**

```bash
git add web/app/\(admin\)/feature-flags/
git commit -m "feat(web): add feature-flags admin page + toggle list"
```

---

### Task 5: Sidebar + layout navigation (superadmin-only link)

**Files:**
- Modify: `web/app/(admin)/layout.tsx`
- Modify: `web/components/dashboard/sidebar.tsx`

**Interfaces:**
- Consumes: `isSuperadmin` (Task 1).
- Produces: `<Sidebar>` gains an `isSuperadmin?: boolean` prop; renders a "Feature Flags" item when true.

- [ ] **Step 1: Pass `isSuperadmin` from the layout into the sidebar**

In `web/app/(admin)/layout.tsx`, add the import near the other imports (after the `Sidebar` import on line 5):

```tsx
import { isSuperadmin } from '@/lib/superadmin'
```

Then, where `userName` is derived (currently `const userName = profile.full_name ?? 'Admin'` on line 36), add below it:

```tsx
  const superadmin = isSuperadmin(user)
```

Change the desktop sidebar render (line 40) from:

```tsx
      <Sidebar userName={userName} />
```

to:

```tsx
      <Sidebar userName={userName} isSuperadmin={superadmin} />
```

- [ ] **Step 2: Add the conditional item to the mobile top-nav**

In the same file, the mobile nav maps over an inline array (lines 48-53). Replace that array literal:

```tsx
              {[
                { href: '/', label: 'Today' },
                { href: '/overview', label: 'Overview' },
                { href: '/students', label: 'Students' },
                { href: '/users', label: 'Users' },
              ].map(item => (
```

with one that conditionally includes the flags link:

```tsx
              {[
                { href: '/', label: 'Today' },
                { href: '/overview', label: 'Overview' },
                { href: '/students', label: 'Students' },
                { href: '/users', label: 'Users' },
                ...(superadmin ? [{ href: '/feature-flags', label: 'Flags' }] : []),
              ].map(item => (
```

- [ ] **Step 3: Add the conditional nav item to the Sidebar**

In `web/components/dashboard/sidebar.tsx`:

Add `Flag` to the lucide import (line 6):

```tsx
import { CalendarDays, BarChart3, Users, UserPlus, Flag } from 'lucide-react'
```

Update the signature (line 17) from:

```tsx
export function Sidebar({ userName }: { userName: string }) {
```

to:

```tsx
export function Sidebar({ userName, isSuperadmin = false }: { userName: string; isSuperadmin?: boolean }) {
```

Then build the nav list inside the component so the flags item is appended only for the superadmin. Replace the module-level `NAV` usage: keep the existing `const NAV = [...]` (lines 10-15) as the base, and inside the component body (right after `const pathname = usePathname()` on line 18) add:

```tsx
  const nav = isSuperadmin
    ? [...NAV, { href: '/feature-flags', label: 'Feature Flags', Icon: Flag }]
    : NAV
```

Then change the `.map` on line 37 from `NAV.map(...)` to `nav.map(...)`:

```tsx
        {nav.map(({ href, label, Icon }) => {
```

- [ ] **Step 4: Build to verify the wiring**

Run: `cd web && npm run build`
Expected: build succeeds, no type errors.

- [ ] **Step 5: Commit**

```bash
git add web/app/\(admin\)/layout.tsx web/components/dashboard/sidebar.tsx
git commit -m "feat(web): show Feature Flags nav link to superadmin only"
```

---

### Task 6: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Lint the whole web package**

Run: `cd web && npm run lint`
Expected: no errors.

- [ ] **Step 2: Production build**

Run: `cd web && npm run build`
Expected: build succeeds; `/feature-flags` appears in the route list.

- [ ] **Step 3: Manual check — superadmin**

With `npm run dev`, sign in as `edmund@thegoodcompanysg.dev`:
- "Feature Flags" appears in the sidebar (and mobile nav).
- `/feature-flags` lists the seeded flags (`parent_portal`, `push_notifications`, `student_photos`).
- Toggling a flag persists across a page reload.

- [ ] **Step 4: Manual check — ordinary admin**

Sign in as a different admin account:
- No "Feature Flags" link in the sidebar/mobile nav.
- Visiting `/feature-flags` directly returns a 404.

- [ ] **Step 5: Final commit (if any verification fixes were needed)**

```bash
git add -A
git commit -m "chore(web): verification fixes for feature-flags section"
```

(Skip if nothing changed.)

---

## Self-Review

**Spec coverage:**
- `lib/superadmin.ts` gate → Task 1 ✓
- Env var `SUPERADMIN_EMAIL` + `.env.local.example` → Task 1 ✓
- `feature-flags/page.tsx` with `notFound()` gate + dynamic flag read → Task 4 ✓
- `flags-list.tsx` client toggles with optimistic + revert + inline error → Task 4 ✓
- `actions/feature-flags.ts` re-check + key validation + RLS update + revalidate → Task 3 ✓
- `components/ui/switch.tsx` → Task 2 ✓
- Sidebar + layout conditional link (desktop + mobile) → Task 5 ✓
- App-layer only, no migration touched → respected (no SQL tasks) ✓
- Verification via lint/build/manual → Task 6 ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✓

**Type consistency:** `FlagRow` defined in `flags-list.tsx`, imported by `page.tsx`. `setFeatureFlag(key, enabled)` signature consistent across Tasks 3–4. `Switch` props (`checked`, `onCheckedChange`, `disabled`, `aria-label`) consistent across Tasks 2 and 4. `isSuperadmin(user)` consistent across Tasks 1, 3, 4, 5. ✓

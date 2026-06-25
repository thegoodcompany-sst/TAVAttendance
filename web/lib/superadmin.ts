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

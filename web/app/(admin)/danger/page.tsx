import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'
import { PageHeader } from '@/components/dashboard/page-header'
import { WipeForm } from './wipe-form'

const WIPED = [
  'Students and their enrolments',
  'All classes (except the internal Study Space)',
  'Sessions and attendance records',
  'Dismissals',
  'Tutor-entered results',
  'Consent records, correction requests, disclosure log',
  'Parent ↔ student links',
  'Audit-log snapshots for the above',
]

const KEPT = [
  'Staff and parent accounts (logins, roles)',
  'Feature flags and app configuration',
  'Data Protection Notice versions',
  'The Study Space class (its sessions/records are still wiped)',
]

export default async function DangerPage() {
  const supabase = await createClient()
  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError) throw authError

  if (!isSuperadmin(user)) notFound()

  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <PageHeader
        title="Pre-launch data wipe"
        subtitle="Permanently clears all operational and roster data. Accounts and configuration are kept."
      />

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="bg-white rounded-2xl border border-destructive/30 shadow-sm overflow-hidden">
          <div className="px-5 py-3 border-b border-destructive/20 bg-destructive/5">
            <h2 className="text-sm font-semibold text-destructive">Wiped</h2>
          </div>
          <ul className="px-5 py-4 space-y-1.5 text-sm text-foreground list-disc list-inside">
            {WIPED.map(item => <li key={item}>{item}</li>)}
          </ul>
        </div>

        <div className="bg-white rounded-2xl border border-border shadow-sm overflow-hidden">
          <div className="px-5 py-3 border-b border-border bg-muted">
            <h2 className="text-sm font-semibold text-foreground">Kept</h2>
          </div>
          <ul className="px-5 py-4 space-y-1.5 text-sm text-foreground list-disc list-inside">
            {KEPT.map(item => <li key={item}>{item}</li>)}
          </ul>
        </div>
      </div>

      <div className="bg-white rounded-2xl border border-destructive/30 shadow-sm p-6">
        <h2 className="text-sm font-semibold text-destructive">This cannot be undone</h2>
        <p className="text-sm text-muted-foreground mt-1 mb-5">
          Type <code className="text-[13px] font-medium text-foreground bg-muted px-1.5 py-0.5 rounded">WIPE ALL DATA</code> to
          enable the button.
        </p>
        <WipeForm />
      </div>
    </div>
  )
}

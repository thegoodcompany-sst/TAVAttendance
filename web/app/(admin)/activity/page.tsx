import { PageHeader } from '@/components/dashboard/page-header'
import { getAuditActors, getAuditLog, getRecentEvents } from '@/lib/queries'
import { ActivityClient } from './activity-client'

export const dynamic = 'force-dynamic'

export default async function ActivityPage({
  searchParams,
}: {
  searchParams: Promise<{
    user?: string
    table?: string
    before?: string
    platform?: string
    type?: string
  }>
}) {
  const filters = await searchParams
  const [audit, actors, events] = await Promise.all([
    getAuditLog({ user: filters.user, table: filters.table, before: filters.before }),
    getAuditActors(),
    getRecentEvents({ platform: filters.platform, type: filters.type }),
  ])

  return (
    <div className="max-w-7xl mx-auto space-y-6">
      <PageHeader title="Activity" subtitle="Staff changes and app events" />
      <ActivityClient audit={audit} actors={actors} events={events} />
    </div>
  )
}

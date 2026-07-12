import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/dashboard/page-header'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { getAwardCandidates, getAwardsForPeriod } from '@/lib/queries'
import { todayInTz } from '@/lib/date'
import { AwardsClient } from './awards-client'

export const dynamic = 'force-dynamic'

// Last 6 calendar months as YYYY-MM labels, current first.
function recentPeriods(): string[] {
  const [y, m] = todayInTz().split('-').map(Number)
  const out: string[] = []
  for (let i = 0; i < 6; i++) {
    const d = new Date(Date.UTC(y, m - 1 - i, 1))
    out.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`)
  }
  return out
}

export default async function AwardsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>
}) {
  if (!(await isFeatureEnabled('awards'))) notFound()

  const periods = recentPeriods()
  const { period: rawPeriod } = await searchParams
  const period = rawPeriod && periods.includes(rawPeriod) ? rawPeriod : periods[0]

  const [candidates, given] = await Promise.all([
    getAwardCandidates(),
    getAwardsForPeriod(period),
  ])

  const byAttendance = [...candidates]
    .sort((a, b) => b.attendancePct - a.attendancePct || b.totalSessions - a.totalSessions)
    .slice(0, 10)
  const byPunctuality = [...candidates]
    .sort((a, b) => a.lateCount - b.lateCount || b.attendancePct - a.attendancePct)
    .slice(0, 10)

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <PageHeader title="Awards" subtitle="Recognise attendance and punctuality" />
      <AwardsClient
        period={period}
        periods={periods}
        byAttendance={byAttendance}
        byPunctuality={byPunctuality}
        given={given}
      />
    </div>
  )
}

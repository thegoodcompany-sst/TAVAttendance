import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/dashboard/page-header'
import { KpiTile } from '@/components/dashboard/kpi-tile'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { getHealthMetrics, getWeeklyAttendanceTrend } from '@/lib/queries'
import { dateOffsetInTz, todayInTz, weekStartOf } from '@/lib/date'
import { HealthEventsChart } from './health-client'

export const dynamic = 'force-dynamic'

type Status = 'green' | 'amber' | 'red'

function rateStatus(value: number): Status {
  if (value < 1) return 'green'
  if (value >= 5) return 'red'
  return 'amber'
}

function crashStatus(value: number): Status {
  if (value === 0) return 'green'
  if (value >= 3) return 'red'
  return 'amber'
}

function latencyStatus(current: number, delta: number): Status {
  if (current >= 5_000 || delta > 50) return 'red'
  if (current >= 2_000 || delta > 0) return 'amber'
  return 'green'
}

function attendanceStatus(value: number): Status {
  if (value >= 90) return 'green'
  if (value >= 75) return 'amber'
  return 'red'
}

export default async function HealthPage() {
  if (!(await isFeatureEnabled('analytics'))) notFound()

  const [health, attendance] = await Promise.all([
    getHealthMetrics(),
    getWeeklyAttendanceTrend(),
  ])
  const currentWeek = weekStartOf(todayInTz())
  const previousWeek = weekStartOf(dateOffsetInTz(-7))
  const currentAttendance = attendance.find(point => point.weekStart === currentWeek)?.attendancePct
  const previousAttendance = attendance.find(point => point.weekStart === previousWeek)?.attendancePct
  const attendanceDelta = currentAttendance != null && previousAttendance != null
    ? Math.round((currentAttendance - previousAttendance) * 10) / 10
    : undefined
  const hasEvents = health.eventCount.current > 0
  const hasSync = health.syncAttempts.current > 0

  return (
    <div className="max-w-7xl mx-auto space-y-6">
      <PageHeader title="Health" subtitle="Software health and usage, current Singapore week vs the previous week" />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <KpiTile label="Error rate" value={hasEvents ? `${health.errorRate.current}%` : 'No data'} delta={hasEvents ? health.errorRate.delta : undefined} deltaLabel="% WoW" status={hasEvents ? rateStatus(health.errorRate.current) : undefined} lowerIsBetter />
        <KpiTile label="Crashes" value={hasEvents ? health.crashes.current : 'No data'} delta={hasEvents ? health.crashes.delta : undefined} deltaLabel="% WoW" status={hasEvents ? crashStatus(health.crashes.current) : undefined} lowerIsBetter />
        <KpiTile label="Sync failures" value={hasSync ? `${health.syncFailureRate.current}%` : 'No data'} delta={hasSync ? health.syncFailureRate.delta : undefined} deltaLabel="% WoW" status={hasSync ? rateStatus(health.syncFailureRate.current) : undefined} lowerIsBetter />
        <KpiTile label="Attendance" value={currentAttendance == null ? 'No data' : `${currentAttendance}%`} delta={attendanceDelta} deltaLabel=" pp WoW" status={currentAttendance == null ? undefined : attendanceStatus(currentAttendance)} />
      </div>

      <div className="bg-white rounded-3xl p-6 shadow-card">
        <h2 className="font-display text-lg font-semibold mb-1">Daily traffic and failures</h2>
        <p className="text-xs text-muted-foreground mb-4">All captured staff events; errors include crashes</p>
        <HealthEventsChart points={health.daily} />
      </div>

      <div className="grid lg:grid-cols-[2fr_1fr] gap-6">
        <section className="bg-white rounded-3xl p-6 shadow-card">
          <h2 className="font-display text-lg font-semibold mb-1">Operation latency</h2>
          <p className="text-xs text-muted-foreground mb-4">Highest daily p95 by operation</p>
          {health.latencies.length === 0 ? (
            <p className="text-sm text-muted-foreground py-10 text-center">No timed operations yet.</p>
          ) : (
            <div className="divide-y divide-border">
              {health.latencies.map(item => (
                <div key={item.name} className="flex items-center gap-3 py-3">
                  <span className={`size-2 rounded-full ${latencyStatus(item.current, item.delta) === 'green' ? 'bg-emerald-500' : latencyStatus(item.current, item.delta) === 'amber' ? 'bg-amber-500' : 'bg-rose-500'}`} />
                  <span className="sr-only">{latencyStatus(item.current, item.delta)} status</span>
                  <span className="flex-1 text-sm font-medium">{item.name.replaceAll('_', ' ')}</span>
                  <span className="text-sm tabular-nums">{Math.round(item.current)} ms</span>
                  <span className={`text-xs tabular-nums w-20 text-right ${item.delta > 0 ? 'text-rose-500' : item.delta < 0 ? 'text-emerald-600' : 'text-muted-foreground'}`}>
                    {item.delta > 0 ? '+' : ''}{item.delta}%
                  </span>
                </div>
              ))}
            </div>
          )}
        </section>

        <section className="bg-white rounded-3xl p-6 shadow-card">
          <h2 className="font-display text-lg font-semibold mb-1">Sync outcomes</h2>
          <p className="text-xs text-muted-foreground mb-4">Totals reported by devices this week</p>
          <dl className="space-y-3 text-sm">
            <div className="flex justify-between"><dt className="text-muted-foreground">Synced</dt><dd className="font-semibold tabular-nums">{health.syncTotals.synced}</dd></div>
            <div className="flex justify-between"><dt className="text-muted-foreground">Skipped</dt><dd className="font-semibold tabular-nums">{health.syncTotals.skipped}</dd></div>
            <div className="flex justify-between"><dt className="text-muted-foreground">Ended sessions</dt><dd className="font-semibold tabular-nums">{health.syncTotals.blockedEndedSession}</dd></div>
            <div className="flex justify-between"><dt className="text-muted-foreground">Pending before sync</dt><dd className="font-semibold tabular-nums">{health.syncTotals.pendingBefore}</dd></div>
          </dl>
        </section>
      </div>
    </div>
  )
}

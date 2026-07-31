import { AutoRefresh } from '@/components/auto-refresh'
import { AttendanceChart } from '@/components/dashboard/attendance-chart'
import { ScheduleList } from '@/components/dashboard/schedule-list'
import { ClassTile } from '@/components/dashboard/class-tile'
import { QuickActionsCard } from '@/components/dashboard/quick-actions-card'
import { getTodayRoster, getTodaySessions, getDailyAttendance } from '@/lib/queries'
import { isFeatureEnabled } from '@/lib/feature-flags'

export const dynamic = 'force-dynamic'

function greeting() {
  const h = new Intl.DateTimeFormat('en-SG', {
    timeZone: 'Asia/Singapore',
    hour: 'numeric',
    hour12: false,
  }).format(new Date())
  const hour = parseInt(h, 10)
  if (hour < 12) return 'morning'
  if (hour < 17) return 'afternoon'
  return 'evening'
}

export default async function TodayPage() {
  const [roster, sessions, dailyData, showNotes] = await Promise.all([
    getTodayRoster(),
    getTodaySessions(),
    getDailyAttendance(14),
    isFeatureEnabled('session_notes'),
  ])

  const presentCount  = roster.filter(s => s.status === 'present').length
  const lateCount     = roster.filter(s => s.status === 'late').length
  const totalExpected = roster.length
  const onTimeRate    = totalExpected > 0 ? Math.round((presentCount / totalExpected) * 100) : 0

  const dayLabel = new Intl.DateTimeFormat('en-SG', {
    timeZone: 'Asia/Singapore',
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(new Date())

  const metrics = [
    { label: 'Expected', value: totalExpected },
    { label: 'Present', value: presentCount, accent: true },
    { label: 'Late', value: lateCount },
    { label: 'On-time rate', value: `${onTimeRate}%` },
  ]

  return (
    <>
      <AutoRefresh intervalMs={30000} />

      <div className="mx-auto max-w-7xl">
        <header className="flex flex-col gap-5 border-b border-brand/20 pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="mb-1 text-[0.7rem] font-bold uppercase tracking-[0.16em] text-brand/60">
              Daily register
            </p>
            <h1 className="font-display text-[2rem] font-semibold tracking-tight text-brand-ink sm:text-4xl">
              Good {greeting()}
            </h1>
            <div className="mt-2 flex items-center gap-3">
              <span className="h-1 w-10 bg-accent-marigold" aria-hidden="true" />
              <p className="text-sm text-muted-foreground">{dayLabel}</p>
            </div>
          </div>
          <QuickActionsCard />
        </header>

        <dl className="mt-5 grid grid-cols-2 border-y border-brand/20 sm:grid-cols-4">
          {metrics.map((metric, index) => (
            <div
              key={metric.label}
              className={[
                'relative py-4',
                index % 2 === 1 ? 'border-l border-brand/15 pl-5' : 'pr-5',
                index > 1 ? 'border-t border-brand/15 sm:border-t-0' : '',
                index > 0 ? 'sm:border-l sm:border-brand/15 sm:px-5' : 'sm:pr-5',
              ].join(' ')}
            >
              {metric.accent && (
                <span
                  className="absolute inset-y-3 left-0 w-[3px] bg-accent-marigold sm:left-0"
                  aria-hidden="true"
                />
              )}
              <dt className="text-[0.65rem] font-bold uppercase tracking-[0.14em] text-muted-foreground">
                {metric.label}
              </dt>
              <dd className="mt-1 font-display text-[1.85rem] font-semibold tracking-tight text-brand-ink sm:text-3xl">
                {metric.value}
              </dd>
            </div>
          ))}
        </dl>

        <div className="grid gap-8 py-7 lg:grid-cols-[minmax(0,1fr)_20rem] lg:gap-0">
          <section className="min-w-0 lg:pr-8" aria-labelledby="attendance-heading">
            <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
              <div>
                <h2 id="attendance-heading" className="font-display text-xl font-semibold text-brand-ink">
                  Attendance
                </h2>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Last 14 days · Mon & Thu tuition days
                </p>
              </div>
              <div className="flex items-center gap-4 text-xs text-muted-foreground" aria-label="Chart legend">
                <span className="flex items-center gap-2">
                  <span className="h-0.5 w-5 bg-brand" aria-hidden="true" />
                  Present
                </span>
                <span className="flex items-center gap-2">
                  <span className="h-0.5 w-5 bg-accent-marigold" aria-hidden="true" />
                  Late
                </span>
              </div>
            </div>
            <AttendanceChart data={dailyData} />
          </section>

          <section
            className="border-t border-brand/20 pt-6 lg:border-l lg:border-t-0 lg:pl-8 lg:pt-0"
            aria-labelledby="schedule-heading"
          >
            <div className="mb-3 flex items-baseline justify-between gap-3">
              <h2 id="schedule-heading" className="font-display text-xl font-semibold text-brand-ink">
                Today&apos;s schedule
              </h2>
              <span className="font-mono text-xs tabular-nums text-muted-foreground">
                {sessions.length} class{sessions.length === 1 ? '' : 'es'}
              </span>
            </div>
            <ScheduleList sessions={sessions} />
          </section>
        </div>

        <section className="border-t border-brand/20 pt-5" aria-labelledby="classes-heading">
          <div className="mb-2 flex items-baseline justify-between gap-4">
            <h2 id="classes-heading" className="font-display text-xl font-semibold text-brand-ink">
              Today&apos;s classes
            </h2>
            {sessions.length > 0 && (
              <span className="text-xs text-muted-foreground">
                Attendance updates every 30 seconds
              </span>
            )}
          </div>

          {sessions.length > 0 ? (
            <div className="border-b border-brand/20">
              {sessions.map(s => (
                <ClassTile key={s.sessionId} session={s} showNotes={showNotes} />
              ))}
            </div>
          ) : (
            <div className="border-y border-brand/20 py-8">
              <p className="text-sm font-medium text-foreground">No sessions today.</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Open the iPad kiosk to create today&apos;s sessions.
              </p>
            </div>
          )}
        </section>
      </div>
    </>
  )
}

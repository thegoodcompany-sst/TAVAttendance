import { AutoRefresh } from '@/components/auto-refresh'
import { KpiTile } from '@/components/dashboard/kpi-tile'
import { AttendanceChart } from '@/components/dashboard/attendance-chart'
import { ScheduleList } from '@/components/dashboard/schedule-list'
import { ClassTile } from '@/components/dashboard/class-tile'
import { QuickActionsCard } from '@/components/dashboard/quick-actions-card'
import { getTodayRoster, getTodaySessions, getDailyAttendance, getYesterdayRoster } from '@/lib/queries'

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
  const [roster, sessions, dailyData, yesterdayRoster] = await Promise.all([
    getTodayRoster(),
    getTodaySessions(),
    getDailyAttendance(14),
    getYesterdayRoster(),
  ])

  const presentCount  = roster.filter(s => s.status === 'present').length
  const lateCount     = roster.filter(s => s.status === 'late').length
  const totalExpected = roster.length
  const onTimeRate    = totalExpected > 0 ? Math.round((presentCount / totalExpected) * 100) : 0

  const yPresent  = yesterdayRoster.filter(s => s.status === 'present').length
  const yLate     = yesterdayRoster.filter(s => s.status === 'late').length
  const yExpected = yesterdayRoster.length

  const dayLabel = new Intl.DateTimeFormat('en-SG', {
    timeZone: 'Asia/Singapore',
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(new Date())

  return (
    <>
      <AutoRefresh intervalMs={30000} />

      <div className="max-w-7xl mx-auto space-y-6">
        {/* Page header */}
        <div>
          <h1 className="text-2xl font-bold">Good {greeting()}</h1>
          <p className="text-sm text-muted-foreground mt-0.5">{dayLabel}</p>
        </div>

        {/* Main two-column layout */}
        <div className="flex flex-col lg:flex-row gap-6">
          {/* Left: KPIs + chart */}
          <div className="flex-[2] flex flex-col gap-6 min-w-0">
            {/* KPI tiles */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
              <KpiTile
                label="Expected"
                value={totalExpected}
                delta={totalExpected - yExpected}
              />
              <KpiTile
                label="Present"
                value={presentCount}
                delta={presentCount - yPresent}
                accent
              />
              <KpiTile
                label="Late"
                value={lateCount}
                delta={lateCount - yLate}
              />
              <KpiTile
                label="On-time rate"
                value={`${onTimeRate}%`}
              />
            </div>

            {/* Attendance chart */}
            <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h2 className="font-semibold">Attendance</h2>
                  <p className="text-xs text-muted-foreground mt-0.5">Last 14 days</p>
                </div>
                <div className="flex items-center gap-4 text-xs text-muted-foreground">
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-[var(--color-chart-1)]" />
                    Present
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-[var(--color-chart-2)]" />
                    Late
                  </span>
                </div>
              </div>
              <AttendanceChart data={dailyData} />
            </div>
          </div>

          {/* Right: illustration + schedule */}
          <div className="lg:w-[288px] xl:w-[320px] flex flex-col gap-6 flex-shrink-0">
            <QuickActionsCard />

            <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
              <h2 className="font-semibold mb-4">Today&apos;s schedule</h2>
              <ScheduleList sessions={sessions} />
            </div>
          </div>
        </div>

        {/* Class tiles row */}
        {sessions.length > 0 && (
          <div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {sessions.map((s, i) => (
                <ClassTile key={s.sessionId} session={s} index={i} />
              ))}
            </div>
            <div className="mt-5 flex justify-center">
              <span className="bg-foreground text-background rounded-full px-6 py-2.5 text-sm font-medium cursor-default">
                {sessions.length} class{sessions.length !== 1 ? 'es' : ''} today →
              </span>
            </div>
          </div>
        )}

        {sessions.length === 0 && (
          <div className="bg-white rounded-3xl p-12 text-center shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
            <p className="text-sm text-muted-foreground">
              No sessions today — open the iPad kiosk to create them.
            </p>
          </div>
        )}
      </div>
    </>
  )
}

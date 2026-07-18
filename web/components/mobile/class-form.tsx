'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { saveClass } from '@/app/actions/mobile'
import type { MobileClass } from '@/lib/mobile-queries'

const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const field = 'min-h-12 w-full rounded-2xl border border-input bg-white px-3 text-base outline-none focus:ring-2 focus:ring-brand/20'

export function MobileClassForm({ initial }: { initial?: MobileClass }) {
  const router = useRouter()
  const [name, setName] = useState(initial?.name ?? '')
  const [subject, setSubject] = useState(initial?.subject ?? '')
  const [level, setLevel] = useState(initial?.level ?? '')
  const [scheduleDay, setScheduleDay] = useState(initial?.scheduleDay ?? '')
  const [scheduleTime, setScheduleTime] = useState(initial?.scheduleTime?.slice(0, 5) ?? '')
  const [durationMinutes, setDurationMinutes] = useState(initial?.durationMinutes ?? 90)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  function submit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    startTransition(async () => {
      const result = await saveClass({ id: initial?.id, name, subject, level, scheduleDay, scheduleTime, durationMinutes })
      if (result.error) return setError(result.error)
      router.push(`/mobile/classes/${result.classId}`)
      router.refresh()
    })
  }

  return <form onSubmit={submit} className="space-y-4 rounded-[1.75rem] border border-brand/10 bg-white p-5 shadow-card">
    <label className="block space-y-1.5"><span className="text-sm font-bold">Class name</span><input required value={name} onChange={event => setName(event.target.value)} className={field} placeholder="Sec 2 Math" /></label>
    <div className="grid grid-cols-2 gap-3">
      <label className="block space-y-1.5"><span className="text-sm font-bold">Subject</span><select value={subject} onChange={event => setSubject(event.target.value)} className={field}><option value="">—</option><option>Math</option><option>English</option></select></label>
      <label className="block space-y-1.5"><span className="text-sm font-bold">Level</span><input value={level} onChange={event => setLevel(event.target.value)} className={field} placeholder="Sec 2" /></label>
    </div>
    <div className="grid grid-cols-2 gap-3">
      <label className="block space-y-1.5"><span className="text-sm font-bold">Day</span><select value={scheduleDay} onChange={event => setScheduleDay(event.target.value)} className={field}><option value="">Flexible</option>{weekdays.map(day => <option key={day}>{day}</option>)}</select></label>
      <label className="block space-y-1.5"><span className="text-sm font-bold">Time</span><input type="time" value={scheduleTime} onChange={event => setScheduleTime(event.target.value)} className={field} /></label>
    </div>
    <label className="block space-y-1.5"><span className="text-sm font-bold">Duration</span><select value={durationMinutes} onChange={event => setDurationMinutes(Number(event.target.value))} className={field}>{[30,45,60,75,90,105,120,150,180,210,240].map(value => <option key={value} value={value}>{value} minutes</option>)}</select></label>
    {error && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
    <button disabled={isPending} className="min-h-13 w-full rounded-2xl bg-brand text-sm font-black text-white">{isPending ? 'Saving…' : initial ? 'Save class' : 'Add class'}</button>
  </form>
}

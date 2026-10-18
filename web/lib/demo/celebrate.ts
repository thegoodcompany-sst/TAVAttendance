import { DEMO_COOKIE } from './constants'
import { easterEggFor } from './easter-eggs'

export const DEMO_EGG_EVENT = 'tava-demo-easter-egg'

export type DemoEggEventDetail = { name: string; moment: 'checkIn' | 'profile' }

function inDemo(): boolean {
  if (typeof document === 'undefined') return false
  return document.cookie.split(';').some(part => part.trim().startsWith(`${DEMO_COOKIE}=`))
}

/** Shows a demo Easter egg after a check-in, if this student has one. No-op outside demo mode. */
export function celebrateDemoCheckIn(studentName: string | null | undefined, status?: string | null) {
  if (!studentName || !inDemo() || !easterEggFor(studentName)) return
  if (status && status !== 'present' && status !== 'late') return
  window.dispatchEvent(new CustomEvent<DemoEggEventDetail>(DEMO_EGG_EVENT, { detail: { name: studentName, moment: 'checkIn' } }))
}

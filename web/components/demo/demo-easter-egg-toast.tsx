'use client'

import { useEffect, useState } from 'react'
import { DEMO_EGG_EVENT, type DemoEggEventDetail } from '@/lib/demo/celebrate'
import { easterEggFor, type DemoEasterEgg } from '@/lib/demo/easter-eggs'

/** Listens for demo check-in celebrations and shows a banner. */
export function DemoEasterEggToast() {
  const [egg, setEgg] = useState<{ egg: DemoEasterEgg; key: number } | null>(null)

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined
    const onEgg = (event: Event) => {
      const detail = (event as CustomEvent<DemoEggEventDetail>).detail
      const match = easterEggFor(detail?.name)
      if (!match) return
      setEgg({ egg: match, key: Date.now() })
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => setEgg(null), 3800)
    }
    window.addEventListener(DEMO_EGG_EVENT, onEgg)
    return () => {
      window.removeEventListener(DEMO_EGG_EVENT, onEgg)
      if (timer) clearTimeout(timer)
    }
  }, [])

  if (!egg) return null
  return (
    <div key={egg.key} className="pointer-events-none fixed inset-0 z-[100] overflow-hidden" aria-live="polite">
      <style>{`
        @keyframes tava-demo-pop { from { transform: translate(-50%, -12px) scale(.96); opacity: 0 } to { transform: translate(-50%, 0) scale(1); opacity: 1 } }
      `}</style>
      <div
        role="status"
        className="pointer-events-auto absolute left-1/2 top-6 flex max-w-[92vw] items-center gap-3 rounded-2xl bg-white px-4 py-3 text-sm font-medium text-gray-900 shadow-xl ring-2"
        style={{ animation: 'tava-demo-pop .25s ease-out both', ['--tw-ring-color' as string]: egg.egg.tint }}
      >
        <span className="text-2xl" aria-hidden>{egg.egg.emoji}</span>
        <span>{egg.egg.checkInMessage}</span>
      </div>
    </div>
  )
}

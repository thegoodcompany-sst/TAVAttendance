'use client'

import { useEffect, useState } from 'react'
import { DEMO_EGG_EVENT, type DemoEggEventDetail } from '@/lib/demo/celebrate'
import { easterEggFor, type DemoEasterEgg } from '@/lib/demo/easter-eggs'

const CONFETTI = Array.from({ length: 28 }, (_, i) => ({
  left: (i * 37) % 100,
  delay: (i % 7) * 0.08,
  duration: 1.6 + ((i * 13) % 10) / 10,
  rotate: (i * 47) % 360,
  color: ['#f59e0b', '#ec4899', '#6366f1', '#10b981', '#f97316'][i % 5],
}))

/** Listens for demo check-in celebrations and shows a banner with confetti. */
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
        @keyframes tava-demo-fall { from { transform: translateY(-10vh) rotate(0deg); opacity: 1 } to { transform: translateY(105vh) rotate(540deg); opacity: .2 } }
        @keyframes tava-demo-pop { from { transform: translate(-50%, -12px) scale(.96); opacity: 0 } to { transform: translate(-50%, 0) scale(1); opacity: 1 } }
      `}</style>
      {CONFETTI.map((piece, i) => (
        <span
          key={i}
          className="absolute top-0 block h-2.5 w-1.5 rounded-sm"
          style={{
            left: `${piece.left}%`,
            background: piece.color,
            transform: `rotate(${piece.rotate}deg)`,
            animation: `tava-demo-fall ${piece.duration}s ease-in ${piece.delay}s both`,
          }}
        />
      ))}
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

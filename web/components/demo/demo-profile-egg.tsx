import { easterEggFor } from '@/lib/demo/easter-eggs'

/** A friendly fun-fact card on a demo student's profile. Render only in demo mode. */
export function DemoProfileEgg({ name }: { name: string | null | undefined }) {
  const egg = easterEggFor(name)
  if (!egg) return null
  return (
    <div
      className="flex items-center gap-3 rounded-xl border bg-white px-4 py-3 text-sm shadow-sm"
      style={{ borderColor: egg.tint }}
      data-testid="demo-profile-egg"
    >
      <span className="text-2xl" aria-hidden>{egg.emoji}</span>
      <span className="text-gray-800">{egg.profileMessage}</span>
    </div>
  )
}

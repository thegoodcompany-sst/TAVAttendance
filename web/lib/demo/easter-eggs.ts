/**
 * Friendly surprises for a few familiar names on the demo roster. Kept in sync
 * with iOS/TAVAttendance/Demo/DemoEasterEggs.swift.
 */
export type DemoEasterEgg = {
  name: string
  emoji: string
  /** Shown when the student is signed in / marked present or late. */
  checkInMessage: string
  /** Shown on the student's profile. */
  profileMessage: string
  /** Tailwind-friendly accent colour. */
  tint: string
}

export const DEMO_EASTER_EGGS: readonly DemoEasterEgg[] = [
  {
    name: 'Lauren Tan',
    emoji: '🌟',
    checkInMessage: 'Lauren Tan is here! Perfect attendance streak continues.',
    profileMessage: "Fun fact: Lauren hasn't missed a single class all year.",
    tint: '#eab308',
  },
  {
    name: 'Brian Chew',
    emoji: '🏀',
    checkInMessage: 'Brian Chew checks in. Nothing but net!',
    profileMessage: 'Fun fact: Brian once explained fractions using basketball stats. It worked.',
    tint: '#f97316',
  },
  {
    name: 'Agrim Singh',
    emoji: '🚀',
    checkInMessage: 'Agrim Singh has landed. Mission control: all systems go!',
    profileMessage: 'Fun fact: Agrim asks the best "but why?" questions in class.',
    tint: '#6366f1',
  },
  {
    name: 'Nick Chan',
    emoji: '🎉',
    checkInMessage: 'Nick Chan is in the house! High-fives all round.',
    profileMessage: 'Fun fact: Nick holds the centre record for most high-fives in one evening.',
    tint: '#ec4899',
  },
]

export function easterEggFor(fullName: string | null | undefined): DemoEasterEgg | null {
  const key = (fullName ?? '').trim().toLowerCase()
  return DEMO_EASTER_EGGS.find(egg => egg.name.toLowerCase() === key) ?? null
}

'use client'

// Catches the errors that lib/queries.ts throws on Supabase failure, so a
// transient blip renders a styled retry page instead of the raw Next error screen.
export default function AdminError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  return (
    <div className="max-w-md mx-auto mt-24 text-center space-y-4 px-6">
      <h1 className="font-display text-xl font-semibold">Something went wrong</h1>
      <p className="text-sm text-muted-foreground">
        We couldn’t load this page. This is usually temporary — please try again.
      </p>
      {error?.message ? (
        <p className="text-xs text-muted-foreground/70 break-words">{error.message}</p>
      ) : null}
      <button
        onClick={reset}
        className="inline-flex items-center rounded-full bg-brand-ink px-5 py-2 text-sm font-medium text-white transition-colors hover:opacity-90"
      >
        Try again
      </button>
    </div>
  )
}

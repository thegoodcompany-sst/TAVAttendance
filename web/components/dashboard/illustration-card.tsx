export function IllustrationCard() {
  return (
    <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-violet-500 via-purple-500 to-fuchsia-600 p-6 text-white min-h-[180px] flex flex-col justify-between">
      {/* Decorative blobs */}
      <div className="absolute -right-10 -top-10 w-44 h-44 rounded-full bg-white/10 pointer-events-none" />
      <div className="absolute -right-3 top-20 w-28 h-28 rounded-full bg-white/10 pointer-events-none" />
      <div className="absolute left-4 -bottom-8 w-20 h-20 rounded-full bg-white/10 pointer-events-none" />

      <div className="relative">
        <span className="inline-block bg-white/20 backdrop-blur-sm rounded-full px-3 py-1 text-xs font-medium mb-3">
          Kiosk
        </span>
        <h3 className="text-xl font-bold leading-snug mb-1">Sign-in Kiosk</h3>
        <p className="text-sm text-white/80 leading-relaxed">
          Open the iPad kiosk to let students sign in to today&apos;s classes.
        </p>
      </div>

      <div className="relative mt-4">
        <span className="inline-block bg-white text-violet-700 font-semibold rounded-full px-4 py-2 text-sm cursor-default">
          Learn more →
        </span>
      </div>
    </div>
  )
}

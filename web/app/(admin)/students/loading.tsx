import { Skeleton } from '@/components/ui/skeleton'

export default function Loading() {
  return (
    <div className="max-w-7xl mx-auto space-y-6">
      <div className="space-y-2">
        <Skeleton className="h-8 w-32 rounded-xl" />
        <Skeleton className="h-4 w-40 rounded-lg" />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <Skeleton key={i} className="h-32 rounded-3xl" />
        ))}
      </div>
    </div>
  )
}

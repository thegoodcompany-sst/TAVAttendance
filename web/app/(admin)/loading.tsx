import { Skeleton } from '@/components/ui/skeleton'

export default function Loading() {
  return (
    <div className="max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="space-y-2">
        <Skeleton className="h-8 w-48 rounded-xl" />
        <Skeleton className="h-4 w-32 rounded-lg" />
      </div>

      {/* KPI tiles */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-3xl" />
        ))}
      </div>

      {/* Chart + side panel */}
      <div className="flex flex-col lg:flex-row gap-6">
        <Skeleton className="flex-[2] h-64 rounded-3xl" />
        <div className="lg:w-[288px] xl:w-[320px] flex flex-col gap-6">
          <Skeleton className="h-32 rounded-3xl" />
          <Skeleton className="h-48 rounded-3xl" />
        </div>
      </div>

      {/* Class tiles */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-32 rounded-3xl" />
        ))}
      </div>
    </div>
  )
}

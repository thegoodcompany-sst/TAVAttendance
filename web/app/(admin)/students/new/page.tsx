import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { NewStudentForm } from './form'

export const dynamic = 'force-dynamic'

export default function NewStudentPage() {
  return (
    <div className="max-w-xl mx-auto space-y-6">
      <Link
        href="/students"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <ArrowLeft size={14} />
        All students
      </Link>

      <div>
        <h1 className="text-2xl font-bold">Add student</h1>
        <p className="text-sm text-muted-foreground mt-0.5">
          Record a new student and attest that parent/guardian consent was obtained.
        </p>
      </div>

      <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
        <NewStudentForm />
      </div>
    </div>
  )
}

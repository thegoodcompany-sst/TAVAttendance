import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { NewStudentForm } from './form'
import { PageHeader } from '@/components/dashboard/page-header'

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

      <PageHeader
        title="Add student"
        subtitle="Record a new student and attest that parent/guardian consent was obtained."
      />

      <div className="bg-white rounded-3xl p-6 shadow-card">
        <NewStudentForm />
      </div>
    </div>
  )
}

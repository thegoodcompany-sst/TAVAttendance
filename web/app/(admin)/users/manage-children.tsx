'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { linkParentStudent, unlinkParentStudent } from '@/app/actions/parent-links'
import { ChevronDown, ChevronUp } from 'lucide-react'

type Student = { id: string; fullName: string }

export function ManageChildren({
  parentId,
  students,
  linkedStudentIds,
}: {
  parentId: string
  students: Student[]
  linkedStudentIds: string[]
}) {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  const toggle = (studentId: string, linked: boolean) => {
    setError(null)
    startTransition(async () => {
      const { error } = linked
        ? await unlinkParentStudent(parentId, studentId)
        : await linkParentStudent(parentId, studentId)
      if (error) setError(error)
      else router.refresh()
    })
  }

  return (
    <div>
      <button
        onClick={() => setOpen(o => !o)}
        className="text-xs font-medium text-brand hover:text-brand-ink transition-colors flex items-center gap-1"
      >
        Manage children
        {open ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
      </button>
      {open && (
        <div className="mt-2 border border-border rounded-xl p-3 space-y-1.5 max-h-56 overflow-y-auto">
          {error && <p className="text-xs text-destructive">{error}</p>}
          {students.length === 0 ? (
            <p className="text-xs text-muted-foreground">No active students.</p>
          ) : (
            students.map(s => {
              const linked = linkedStudentIds.includes(s.id)
              return (
                <label key={s.id} className="flex items-center gap-2 text-xs text-foreground">
                  <input
                    type="checkbox"
                    checked={linked}
                    disabled={isPending}
                    onChange={() => toggle(s.id, linked)}
                    className="rounded border-border"
                  />
                  {s.fullName}
                </label>
              )
            })
          )}
        </div>
      )}
    </div>
  )
}

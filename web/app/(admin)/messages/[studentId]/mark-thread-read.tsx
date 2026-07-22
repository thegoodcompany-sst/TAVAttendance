'use client'

import { useEffect, useRef } from 'react'
import { markThreadRead } from '@/app/actions/messages'

export function MarkThreadRead({
  studentId,
  parentId,
}: {
  studentId: string
  parentId: string
}) {
  const attempted = useRef(false)

  useEffect(() => {
    if (attempted.current) return
    attempted.current = true
    void markThreadRead(studentId, parentId)
  }, [studentId, parentId])

  return null
}

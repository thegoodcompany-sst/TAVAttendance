import { Suspense } from 'react'
import { SetPasswordForm } from './form'

export default function SetPasswordPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-surface" />}>
      <SetPasswordForm />
    </Suspense>
  )
}

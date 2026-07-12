'use client'

import { Printer } from 'lucide-react'

export function PrintButton() {
  return (
    <button
      onClick={() => window.print()}
      className="inline-flex items-center gap-1.5 text-sm font-medium text-white/90 hover:text-white transition-colors print:hidden"
    >
      <Printer size={15} /> Print
    </button>
  )
}

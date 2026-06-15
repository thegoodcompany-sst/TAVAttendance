import { AlertTriangle } from 'lucide-react'

/**
 * Inline PDPA data-minimisation guidance for free-text notes fields.
 * The database also rejects NRIC/FIN-pattern notes server-side; this is the
 * advisory shown at the input.
 */
export function NricWarning() {
  return (
    <p className="flex items-start gap-1.5 text-xs text-amber-700">
      <AlertTriangle size={12} className="mt-0.5 flex-shrink-0" />
      <span>Do not enter NRIC/FIN or other sensitive identifiers (PDPA).</span>
    </p>
  )
}

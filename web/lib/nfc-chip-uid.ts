const HEX = /[^0-9A-Fa-f]/g

/** Same rules as public.normalize_nfc_chip_uid: uppercase hex, 8–20 chars, even length. */
export function normalizeNfcChipUid(raw: string | null | undefined): string | null {
  if (raw == null) return null
  const hex = raw.replace(HEX, '').toUpperCase()
  if (hex.length < 8 || hex.length > 20 || hex.length % 2 !== 0) return null
  if (!/^[0-9A-F]+$/.test(hex)) return null
  return hex
}

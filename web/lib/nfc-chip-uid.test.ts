import { describe, expect, it } from 'vitest'
import { normalizeNfcChipUid } from './nfc-chip-uid'

describe('normalizeNfcChipUid', () => {
  it('strips colons and spaces and uppercases', () => {
    expect(normalizeNfcChipUid('04:a1:b2:c3')).toBe('04A1B2C3')
    expect(normalizeNfcChipUid(' 04a1b2c3d4e5f6 ')).toBe('04A1B2C3D4E5F6')
  })

  it('rejects garbage, odd length, and empty', () => {
    expect(normalizeNfcChipUid('zzzz')).toBeNull()
    expect(normalizeNfcChipUid('ABC')).toBeNull()
    expect(normalizeNfcChipUid('')).toBeNull()
    expect(normalizeNfcChipUid(null)).toBeNull()
  })
})

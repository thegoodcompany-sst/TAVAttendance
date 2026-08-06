import { describe, expect, it } from 'vitest'
import { rosterStatusLabel, statusLabel } from './status'

describe('statusLabel', () => {
  it('labels unmarked as Not here yet', () => {
    expect(statusLabel(null)).toBe('Not here yet')
  })

  it('labels present and late', () => {
    expect(statusLabel('present')).toBe('On time')
    expect(statusLabel('late')).toBe('Late')
  })

  it('splits absent by absence_informed companion flag', () => {
    expect(statusLabel('absent', true)).toBe('Absent (informed)')
    expect(statusLabel('absent', false)).toBe('Absent (no notice)')
    expect(statusLabel('absent', null)).toBe('Absent')
    expect(statusLabel('absent')).toBe('Absent')
  })
})

describe('rosterStatusLabel', () => {
  it('uses Present instead of On time', () => {
    expect(rosterStatusLabel('present')).toBe('Present')
  })

  it('splits absent the same way as statusLabel', () => {
    expect(rosterStatusLabel('absent', true)).toBe('Absent (informed)')
    expect(rosterStatusLabel('absent', false)).toBe('Absent (no notice)')
    expect(rosterStatusLabel('absent', null)).toBe('Absent')
  })
})

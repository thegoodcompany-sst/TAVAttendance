import { describe, expect, it } from 'vitest'
import { parseStudentCsv } from './csv'

describe('student CSV import', () => {
  it('keeps multiline quoted notes in one student record', () => {
    expect(parseStudentCsv('full_name,date_of_birth,school,year_of_study,notes\r\nExample Student,,"Example, School",P4,"First line\r\nSecond ""quoted"" line"\r\n')).toEqual([
      { fullName: 'Example Student', dateOfBirth: null, school: 'Example, School', yearOfStudy: 'P4', notes: 'First line\r\nSecond "quoted" line' },
    ])
  })

  it('accepts a BOM, blank lines, short rows, and CR record separators', () => {
    expect(parseStudentCsv('\uFEFFname,date_of_birth,school,year_of_study,notes\r\rExample Student\r')).toEqual([
      { fullName: 'Example Student', dateOfBirth: null, school: null, yearOfStudy: null, notes: null },
    ])
  })

  it.each([
    'Example Student,,,,"Unclosed note',
    'Example Student,,,,unquoted"note',
    'Example Student,,,,"note"trailing',
    'Example Student,,,,note,unexpected column',
  ])('rejects malformed input before creating any students', text => {
    expect(() => parseStudentCsv(text)).toThrow(/CSV row 1/)
  })

  it('keeps deliberately empty first cells for server validation', () => {
    expect(parseStudentCsv(',2012-01-01,Example School,P4,')).toHaveLength(1)
    expect(parseStudentCsv(',2012-01-01,Example School,P4,')[0].fullName).toBe('')
  })
})

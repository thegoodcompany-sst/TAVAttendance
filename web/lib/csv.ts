export type ParsedStudentRow = {
  fullName: string
  dateOfBirth: string | null
  school: string | null
  yearOfStudy: string | null
  notes: string | null
}

/**
 * Parse a single CSV line respecting double-quoted fields (RFC-4180 subset:
 * commas and escaped "" inside quotes are honoured; embedded newlines are not).
 */
function parseCsvLine(line: string): string[] {
  const out: string[] = []
  let cur = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          cur += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        cur += ch
      }
    } else if (ch === '"') {
      inQuotes = true
    } else if (ch === ',') {
      out.push(cur)
      cur = ''
    } else {
      cur += ch
    }
  }
  out.push(cur)
  return out.map(s => s.trim())
}

/**
 * Parse pasted CSV text into student rows. Column order is fixed:
 * full_name, date_of_birth, school, year_of_study, notes.
 * A leading header row (first cell case-insensitively "full_name"/"name") is
 * skipped. Blank lines are ignored.
 */
export function parseStudentCsv(text: string): ParsedStudentRow[] {
  const lines = text
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(l => l.length > 0)

  if (lines.length === 0) return []

  const startIdx = (() => {
    const first = parseCsvLine(lines[0])[0]?.toLowerCase()
    return first === 'full_name' || first === 'name' ? 1 : 0
  })()

  const rows: ParsedStudentRow[] = []
  for (let i = startIdx; i < lines.length; i++) {
    const cells = parseCsvLine(lines[i])
    rows.push({
      fullName: cells[0] ?? '',
      dateOfBirth: cells[1] || null,
      school: cells[2] || null,
      yearOfStudy: cells[3] || null,
      notes: cells[4] || null,
    })
  }
  return rows
}

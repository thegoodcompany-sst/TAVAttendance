export type ParsedStudentRow = {
  fullName: string
  dateOfBirth: string | null
  school: string | null
  yearOfStudy: string | null
  notes: string | null
}

export function parseStudentCsv(text: string): ParsedStudentRow[] {
  const records: string[][] = []
  let cells: string[] = []
  let field = ''
  let state: 'unquoted' | 'quoted' | 'closed' = 'unquoted'
  let row = 1
  const invalid = (reason: string): never => {
    throw new Error(`CSV row ${row}: ${reason}`)
  }
  const finishField = () => {
    cells.push(field.trim())
    field = ''
    state = 'unquoted'
  }
  const finishRecord = () => {
    finishField()
    if (cells.length > 5) invalid('Expected at most 5 columns. Quote fields containing commas.')
    if (cells.some(cell => cell.length > 0)) records.push(cells)
    cells = []
    row++
  }

  const source = text.replace(/^\uFEFF/, '')
  for (let i = 0; i < source.length; i++) {
    const char = source[i]
    if (state === 'quoted') {
      if (char !== '"') field += char
      else if (source[i + 1] === '"') {
        field += '"'
        i++
      } else state = 'closed'
    } else if (char === ',') {
      finishField()
    } else if (char === '\r' || char === '\n') {
      finishRecord()
      if (char === '\r' && source[i + 1] === '\n') i++
    } else if (state === 'closed') {
      if (char !== ' ' && char !== '\t') invalid('Unexpected text after a closing quote.')
    } else if (char === '"') {
      if (field.trim()) invalid('A quote must start a field. Use double quotes to escape quotes.')
      field = ''
      state = 'quoted'
    } else {
      field += char
    }
  }
  if (state === 'quoted') invalid('A quoted field is not closed.')
  finishRecord()

  const first = records[0]?.[0]?.toLowerCase()
  if (first === 'full_name' || first === 'name') records.shift()
  return records.map(cells => ({
    fullName: cells[0] ?? '',
    dateOfBirth: cells[1] || null,
    school: cells[2] || null,
    yearOfStudy: cells[3] || null,
    notes: cells[4] || null,
  }))
}

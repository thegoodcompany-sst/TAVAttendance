import { beforeEach, expect, it, vi } from 'vitest'
import type { FormEvent, ReactElement } from 'react'
const mocks = vi.hoisted(() => ({ prepare: vi.fn(), finalize: vi.fn(), upload: vi.fn(), refresh: vi.fn(), error: vi.fn(), tasks: [] as Promise<void>[], hooks: [] as unknown[], cursor: 0 }))
vi.mock('react', async original => ({
  ...await original<typeof import('react')>(),
  useRef: (current: unknown) => {
    const index = mocks.cursor++
    return mocks.hooks[index] ??= { current }
  },
  useState: (initial: unknown) => {
    const index = mocks.cursor++
    if (!(index in mocks.hooks)) mocks.hooks[index] = initial
    return [mocks.hooks[index], (value: unknown) => {
      mocks.hooks[index] = value
      mocks.error(value)
    }]
  },
  useTransition: () => [false, (task: () => Promise<void>) => mocks.tasks.push(task())],
}))
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: mocks.refresh }) }))
vi.mock('@/app/actions/parent-portal', () => ({ prepareResultSlipUpload: mocks.prepare, finalizeResultSlipUpload: mocks.finalize }))
vi.mock('@/lib/supabase/client', () => ({ createClient: () => ({ storage: { from: () => ({ uploadToSignedUrl: mocks.upload }) } }) }))
import { UploadForm } from '@/app/parent/results/[studentId]/upload-form'

beforeEach(() => {
  vi.clearAllMocks()
  mocks.tasks = []
  mocks.hooks = []
  mocks.cursor = 0
  mocks.prepare.mockResolvedValue({ path: 'student/original.pdf', token: 'synthetic', error: null })
  mocks.upload.mockResolvedValue({ error: null })
  mocks.finalize.mockResolvedValue({ error: null })
})

it('resumes after a lost commit response without preparing or uploading again', async () => {
  const data = new FormData()
  data.set('file', new File(['%PDF-test'], 'test.pdf', { type: 'application/pdf' }))
  data.set('exam_name', 'Original exam')
  vi.stubGlobal('FormData', class { constructor() { return data } })
  try {
    const committed = new Set<string>()
    mocks.finalize.mockImplementationOnce(async (_student, upload) => {
      committed.add(upload.path)
      throw new Error('response lost')
    }).mockImplementationOnce(async (_student, upload) => {
      committed.add(upload.path)
      return { error: null }
    })
    const form = UploadForm({ studentId: 'student' })
    const submit = () => form.props.onSubmit({ preventDefault() {}, currentTarget: {} } as FormEvent<HTMLFormElement>)
    submit()
    await mocks.tasks.at(-1)
    expect(mocks.error).toHaveBeenLastCalledWith(expect.stringContaining('resume'))
    expect(mocks.refresh).not.toHaveBeenCalled()
    data.delete('file')
    data.set('exam_name', 'Changed')
    submit()
    await mocks.tasks.at(-1)
    expect(mocks.prepare).toHaveBeenCalledOnce()
    expect(mocks.upload).toHaveBeenCalledOnce()
    expect(mocks.finalize).toHaveBeenCalledTimes(2)
    expect(mocks.finalize.mock.calls[1]).toEqual(mocks.finalize.mock.calls[0])
    expect(committed.size).toBe(1)
    expect(mocks.refresh).toHaveBeenCalledOnce()
  } finally {
    vi.unstubAllGlobals()
  }
})

it('retains the reservation after an upload failure and clears it only after success', async () => {
  const data = new FormData()
  data.set('file', new File(['%PDF-test'], 'test.pdf', { type: 'application/pdf' }))
  data.set('exam_name', 'Exam')
  vi.stubGlobal('FormData', class { constructor() { return data } })
  try {
    mocks.upload.mockRejectedValueOnce(new Error('connection lost'))
    const form = UploadForm({ studentId: 'student' })
    const submit = async () => {
      form.props.onSubmit({ preventDefault() {}, currentTarget: {} } as FormEvent<HTMLFormElement>)
      await mocks.tasks.at(-1)
    }
    await submit()
    expect(mocks.finalize).not.toHaveBeenCalled()
    await submit()
    expect(mocks.prepare).toHaveBeenCalledOnce()
    expect(mocks.upload).toHaveBeenCalledTimes(2)
    expect(mocks.upload.mock.calls[1]).toEqual(mocks.upload.mock.calls[0])
    expect(mocks.finalize).toHaveBeenCalledOnce()
    await submit()
    expect(mocks.prepare).toHaveBeenCalledTimes(2)
  } finally {
    vi.unstubAllGlobals()
  }
})

function renderForm() {
  mocks.cursor = 0
  return UploadForm({ studentId: 'student' })
}

function restartButton(form: ReturnType<typeof UploadForm>) {
  const controls = form.props.children[2]
  return controls.props.children[1] as ReactElement<{ onClick: () => void; disabled: boolean }>
}

it.each([
  { statusCode: '409', message: 'Duplicate' },
  { statusCode: '400', message: 'The resource already exists' },
  { code: 'ResourceAlreadyExists', message: 'Duplicate' },
])('verifies an existing object after a lost upload response (%j)', async duplicate => {
  const data = new FormData()
  data.set('file', new File(['%PDF-test'], 'test.pdf', { type: 'application/pdf' }))
  data.set('exam_name', 'Exam')
  vi.stubGlobal('FormData', class { constructor() { return data } })
  try {
    mocks.upload.mockRejectedValueOnce(new Error('response lost'))
      .mockResolvedValueOnce({ error: duplicate })
    const form = renderForm()
    const submit = async () => {
      form.props.onSubmit({ preventDefault() {}, currentTarget: {} })
      await mocks.tasks.at(-1)
    }
    await submit()
    await submit()
    expect(mocks.prepare).toHaveBeenCalledOnce()
    expect(mocks.upload.mock.calls[1]).toEqual(mocks.upload.mock.calls[0])
    expect(mocks.finalize).toHaveBeenCalledOnce()
    expect(mocks.refresh).toHaveBeenCalledOnce()
  } finally {
    vi.unstubAllGlobals()
  }
})

it.each([
  'The file contents do not match the selected file type.',
  'Upload authorization is invalid or expired.',
  'Upload verification limit reached or unavailable. Please prepare a new upload.',
])('allows a new file and reservation after: %s', async error => {
  const data = new FormData()
  data.set('file', new File(['bad'], 'bad.pdf', { type: 'application/pdf' }))
  data.set('exam_name', 'Exam')
  vi.stubGlobal('FormData', class { constructor() { return data } })
  vi.stubGlobal('HTMLInputElement', class {})
  try {
    mocks.upload.mockResolvedValueOnce({ error: { statusCode: '409' } })
    mocks.finalize.mockResolvedValueOnce({ error, kind: 'rejected' })
    let form = renderForm()
    form.props.onSubmit({ preventDefault() {}, currentTarget: {} })
    await mocks.tasks.at(-1)
    expect(mocks.refresh).not.toHaveBeenCalled()
    form = renderForm()
    expect(form.props.children[1].props.disabled).toBe(true)
    restartButton(form).props.onClick()
    form = renderForm()
    expect(form.props.children[1].props.disabled).toBe(false)
    expect(form.props.children[0].props.disabled).toBe(false)
    const replacement = new File(['%PDF-good'], 'good.pdf', { type: 'application/pdf' })
    data.set('file', replacement)
    mocks.prepare.mockResolvedValueOnce({ path: 'student/new.pdf', token: 'new', error: null })
    form.props.onSubmit({ preventDefault() {}, currentTarget: {} })
    await mocks.tasks.at(-1)
    expect(mocks.prepare).toHaveBeenCalledTimes(2)
    expect(mocks.upload).toHaveBeenLastCalledWith('student/new.pdf', 'new', replacement, { contentType: 'application/pdf' })
    expect(mocks.finalize.mock.calls[1][1].path).toBe('student/new.pdf')
    expect(mocks.refresh).toHaveBeenCalledOnce()
  } finally {
    vi.unstubAllGlobals()
  }
})

it.each(['ambiguous', 'thrown'])('locks the original metadata and replacement after an %s outcome', async kind => {
  const data = new FormData()
  data.set('file', new File(['%PDF-test'], 'test.pdf', { type: 'application/pdf' }))
  data.set('exam_name', 'Original exam')
  data.set('score', '80')
  vi.stubGlobal('FormData', class { constructor() { return data } })
  try {
    if (kind === 'thrown') mocks.finalize.mockRejectedValueOnce(new Error('response lost'))
    else mocks.finalize.mockResolvedValueOnce({ error: 'Recovery unavailable', kind: 'ambiguous' })
    // An authentication failure cannot resolve the earlier ambiguity.
    mocks.finalize.mockResolvedValueOnce({ error: 'Not authenticated.', kind: 'rejected' })
    const submit = async () => {
      renderForm().props.onSubmit({ preventDefault() {}, currentTarget: {} })
      await mocks.tasks.at(-1)
    }
    await submit()
    expect(renderForm().props.children[0].props.disabled).toBe(true)
    expect(restartButton(renderForm())).toBe(false)
    data.set('exam_name', 'Changed exam')
    data.set('score', '90')
    await submit()
    expect(renderForm().props.children[0].props.disabled).toBe(true)
    expect(restartButton(renderForm())).toBe(false)
    await submit()
    expect(mocks.finalize.mock.calls[1]).toEqual(mocks.finalize.mock.calls[0])
    expect(mocks.finalize.mock.calls[2]).toEqual(mocks.finalize.mock.calls[0])
    expect(mocks.prepare).toHaveBeenCalledOnce()
    expect(mocks.upload).toHaveBeenCalledOnce()
    expect(mocks.refresh).toHaveBeenCalledOnce()
  } finally {
    vi.unstubAllGlobals()
  }
})

it.each(['validation', 'thrown'])('allows metadata correction after definite validation following %s', async initialOutcome => {
  const data = new FormData()
  data.set('file', new File(['%PDF-test'], 'test.pdf', { type: 'application/pdf' }))
  data.set('exam_name', 'Exam')
  data.set('score', '-1')
  vi.stubGlobal('FormData', class { constructor() { return data } })
  try {
    if (initialOutcome === 'thrown') {
      mocks.finalize.mockRejectedValueOnce(new Error('response lost'))
      renderForm().props.onSubmit({ preventDefault() {}, currentTarget: {} })
      await mocks.tasks.at(-1)
      expect(renderForm().props.children[0].props.disabled).toBe(true)
      expect(restartButton(renderForm())).toBe(false)
      // Disabled fields are omitted by browser FormData; retry the saved payload.
      data.delete('exam_name')
      data.delete('score')
    }
    mocks.finalize.mockResolvedValueOnce({ error: 'Score must be zero or greater.', kind: 'validation' })
    renderForm().props.onSubmit({ preventDefault() {}, currentTarget: {} })
    await mocks.tasks.at(-1)
    expect(renderForm().props.children[0].props.disabled).toBe(false)
    expect(restartButton(renderForm()).props.disabled).toBe(false)
    if (initialOutcome === 'thrown') {
      expect(mocks.finalize.mock.calls[1]).toEqual(mocks.finalize.mock.calls[0])
    }
    data.set('exam_name', 'Exam')
    data.set('score', '80')
    renderForm().props.onSubmit({ preventDefault() {}, currentTarget: {} })
    await mocks.tasks.at(-1)
    expect(mocks.finalize.mock.calls.at(-1)?.[1]).toEqual({ ...mocks.finalize.mock.calls[0][1], score: 80 })
    expect(mocks.prepare).toHaveBeenCalledOnce()
    expect(mocks.upload).toHaveBeenCalledOnce()
    expect(mocks.refresh).toHaveBeenCalledOnce()
  } finally {
    vi.unstubAllGlobals()
  }
})

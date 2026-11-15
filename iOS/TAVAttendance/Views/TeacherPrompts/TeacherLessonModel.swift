import Foundation
import Combine
import PromptRouter

@MainActor
final class TeacherLessonModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var projection: TeacherLessonProjection?
    @Published var notes = ""
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published var confirmingSnooze = false
    @Published private(set) var snoozeLimited = false
    @Published private(set) var submitted = false
    private let service: any TeacherPromptServing
    private let allowed: () -> Bool
    private let didSubmit: (UUID) async -> Void
    private let sessionExpired: (UUID) -> Void
    @Published private(set) var reviewingAllPresent = false
    @Published private var draft: [TeacherRosterStudent]?
    private var adjusted = false
    var roster: [TeacherRosterStudent] { draft ?? projection?.roster ?? [] }
    private var valid = true
    private var retryWrite: (() async throws -> Void)?
    private var retryIsSubmission = false
    private var retryIsFeedback = false
    let lessonID: UUID

    init(projection: TeacherLessonProjection, service: any TeacherPromptServing,
         needsSnoozeConfirmation: Bool, allowed: @escaping () -> Bool,
         didSubmit: @escaping (UUID) async -> Void, sessionExpired: @escaping (UUID) -> Void) {
        self.projection = projection; self.service = service; self.allowed = allowed
        self.didSubmit = didSubmit; self.sessionExpired = sessionExpired
        lessonID = projection.lesson.id; notes = projection.feedback.body
        submitted = projection.submission != nil || projection.lesson.state == "submitted"
        confirmingSnooze = needsSnoozeConfirmation && projection.lesson.can_snooze && !submitted
    }
    var canEdit: Bool { valid && allowed() && !busy && !submitted && retryWrite == nil && projection?.lesson.can_edit == true }
    var canSnooze: Bool { valid && allowed() && !busy && !submitted && !snoozeLimited && projection?.lesson.can_snooze == true }
    var hasRetry: Bool { retryWrite != nil }
    var notesDirty: Bool { notes != projection?.feedback.body }
    var canSubmit: Bool {
        canEdit && !notesDirty && (reviewingAllPresent
            ? roster.allSatisfy { $0.status != nil } && (!roster.isEmpty || projection?.lesson.can_submit == true)
            : projection?.lesson.can_submit == true)
    }
    private func clearReview() { draft = nil; reviewingAllPresent = false; adjusted = false }
    private func accept(_ fresh: TeacherLessonProjection) {
        if fresh.lesson.register_revision != projection?.lesson.register_revision || fresh.submission != nil {
            clearReview()
        }
        projection = fresh
    }
    func invalidate() {
        clearReview()
        valid = false; projection = nil; notes = ""; message = nil
        confirmingSnooze = false; retryWrite = nil
    }
    func allPresent() async {
        guard canEdit, let p = projection else { return }
        guard !notesDirty else { return }
        // Review only: no server mutation until the explicit confirmation.
        draft = p.roster.map { student in
            var row = student
            if row.status == nil { row.status = .present }
            return row
        }
        reviewingAllPresent = true; adjusted = false; message = nil
    }
    func mark(_ student: TeacherRosterStudent, status: TeacherAttendanceStatus?, informed: Bool? = nil) async {
        guard canEdit, let p = projection else { return }
        if reviewingAllPresent, let index = draft?.firstIndex(where: { $0.id == student.id }) {
            draft?[index].status = status
            draft?[index].absence_informed = status == .absent ? informed : nil
            adjusted = true
            return
        }
        let m = TeacherMark(p_lesson_id: lessonID, p_student_id: student.id, p_status: status,
            p_absence_informed: status == .absent ? informed : nil, p_observed_marked_at: student.marked_at,
            p_expected_revision: p.lesson.register_revision, p_mutation_id: UUID())
        await write { [service] in _ = try await service.mark(m) }
    }
    func saveNotes() async {
        guard canEdit, let p = projection else { return }
        guard notes.unicodeScalars.count <= 1000 else { message = PromptStrings.feedbackLimit; return }
        let m = TeacherFeedbackMutation(p_lesson_id: lessonID, p_body: notes,
            p_expected_feedback_revision: p.feedback.revision, p_mutation_id: UUID())
        await write(feedback: true) { [service] in try await service.feedback(m) }
    }
    func submit() async {
        guard canSubmit, let p = projection else { return }
        let m = TeacherSubmitMutation(p_lesson_id: lessonID, p_expected_revision: p.lesson.register_revision,
            p_expected_feedback_revision: p.feedback.revision, p_mutation_id: UUID())
        if reviewingAllPresent && !adjusted {
            await write(submission: true) { [service] in try await service.confirmAllPresentAndSubmit(m) }
        } else if reviewingAllPresent {
            let changes = roster.filter { row in
                guard let old = p.roster.first(where: { $0.id == row.id }) else { return false }
                return row.status != old.status || row.absence_informed != old.absence_informed
            }
            // The closure retains its cursor and current request for exact replay after
            // a lost response. Revisions come from receipts, never a guessed increment.
            var index = 0
            var revision = p.lesson.register_revision
            var current: TeacherMark?
            var submission: TeacherSubmitMutation?
            await write(submission: true) { [weak self, service] in
                while index < changes.count {
                    guard let self, self.valid, self.allowed() else { throw CancellationError() }
                    let row = changes[index]
                    if current == nil {
                        current = TeacherMark(p_lesson_id: p.lesson.id, p_student_id: row.id,
                            p_status: row.status, p_absence_informed: row.absence_informed,
                            p_observed_marked_at: row.marked_at, p_expected_revision: revision, p_mutation_id: UUID())
                    }
                    let receipt = try await service.mark(current!)
                    revision = receipt.register_revision
                    index += 1; current = nil
                }
                guard let self, self.valid, self.allowed() else { throw CancellationError() }
                if submission == nil {
                    submission = TeacherSubmitMutation(p_lesson_id: p.lesson.id, p_expected_revision: revision,
                        p_expected_feedback_revision: p.feedback.revision, p_mutation_id: UUID())
                }
                try await service.submit(submission!)
            }
        } else {
            await write(submission: true) { [service] in try await service.submit(m) }
        }
    }
    private func write(submission: Bool = false, feedback: Bool = false,
                       operation: @escaping () async throws -> Void) async {
        guard valid, allowed(), !busy else { return }
        busy = true; message = nil
        retryWrite = operation; retryIsSubmission = submission; retryIsFeedback = feedback
        defer { busy = false }
        do {
            try await operation()
            guard valid, allowed() else { return }
            retryWrite = nil
            if submission {
                clearReview()
                submitted = true; confirmingSnooze = false
                projection?.lesson.state = "submitted"
                projection?.lesson.can_edit = false
                projection?.lesson.can_submit = false
                projection?.lesson.can_snooze = false
                await didSubmit(lessonID)
            }
            let fresh = try await service.lesson(lessonID)
            guard valid, allowed() else { return }
            accept(fresh)
            if feedback { notes = fresh.feedback.body }
        } catch {
            guard valid, allowed() else { return }
            let failure = error as? TeacherPromptError ?? .network
            if failure != .network { retryWrite = nil }
            handle(failure)
            if failure == .conflict || failure == .locked { clearReview(); await reload(keepNotes: true) }
        }
    }
    func retry() async {
        if let operation = retryWrite {
            await write(submission: retryIsSubmission, feedback: retryIsFeedback, operation: operation)
        } else { message = nil; await reload(keepNotes: true) }
    }
    func reload(keepNotes: Bool = true) async {
        guard valid, allowed() else { return }
        do {
            let fresh = try await service.lesson(lessonID)
            guard valid, allowed() else { return }
            accept(fresh)
            if !keepNotes { notes = fresh.feedback.body }
            if fresh.submission != nil || fresh.lesson.state == "submitted" {
                submitted = true; confirmingSnooze = false; retryWrite = nil
                await didSubmit(lessonID)
            }
        } catch {
            guard valid, allowed() else { return }
            handle(error as? TeacherPromptError ?? .network)
        }
    }
    /// Only a visible button invokes this. No replay closure or persisted write.
    func confirmSnooze() async {
        guard confirmingSnooze, canSnooze else { return }
        confirmingSnooze = false; busy = true; message = nil
        defer { busy = false }
        do {
            try await service.snooze(lessonID, mutationID: UUID())
            guard valid, allowed() else { return }
            message = PromptStrings.snoozed
            await reload()
        } catch {
            guard valid, allowed() else { return }
            handle(error as? TeacherPromptError ?? .network)
        }
    }
    private func handle(_ error: TeacherPromptError) {
        message = error.message
        if error == .unavailable || error == .disabled {
            clearReview()
            valid = false; projection = nil; notes = ""; confirmingSnooze = false; retryWrite = nil
        }
        if error == .snoozeLimit || error == .noPrompt { snoozeLimited = true; confirmingSnooze = false }
        if error == .sessionExpired { sessionExpired(lessonID); invalidate() }
    }
}

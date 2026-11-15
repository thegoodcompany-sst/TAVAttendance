import Foundation
import PromptRouter

/// Deterministic, memory-only v2 fixture. Never owns a network client.
@MainActor
final class DemoTeacherPromptService: TeacherPromptServing {
    static let lessonID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    let accountID: UUID
    private(set) var projection: TeacherLessonProjection
    private(set) var snoozeCount = 0
    private var receipts: [UUID: Data] = [:]
    private let instant = "2027-01-07T13:05:00.000001Z"

    init(accountID: UUID = DemoMode.userId) {
        self.accountID = accountID
        let roster = (1...4).map { index in
            TeacherRosterStudent(student_id: UUID(uuidString: String(format: "20000000-0000-4000-8000-%012d", index))!,
                display_name: String(format: "%@ %02d", PromptStrings.demoStudentPrefix, index),
                status: index == 2 ? .late : index == 3 ? .absent : nil,
                absence_informed: index == 3 ? true : nil,
                marked_at: index == 2 || index == 3 ? "2027-01-07T13:00:00.123456Z" : nil)
        }
        projection = TeacherLessonProjection(server_now: "2027-01-07T13:05:00Z", lesson: TeacherLessonSummary(
            lesson_id: Self.lessonID, class_id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            class_label: PromptStrings.demoClass, scheduled_start_at: "2027-01-07T11:00:00Z",
            scheduled_end_at: "2027-01-07T13:00:00Z", state: "awaiting_attendance",
            accountable_teacher_id: accountID, accountable_teacher_label: PromptStrings.demoTeacher,
            is_accountable: true, register_revision: "2", roster_count: roster.count, marked_count: 2,
            next_prompt_at: "2027-01-07T13:15:00Z", overdue_at: "2027-01-08T01:15:00Z",
            can_edit: true, can_submit: false, can_snooze: true),
            roster: roster, feedback: TeacherLessonFeedback(body: "", revision: "0"))
    }
    func lessons() async throws -> TeacherLessons {
        TeacherLessons(server_now: instant, date: "2027-01-07", lessons: [projection.lesson],
                       outstanding_count: projection.submission == nil ? 1 : 0, backlog: [])
    }
    func lesson(_ id: UUID) async throws -> TeacherLessonProjection {
        guard id == Self.lessonID else { throw TeacherPromptError.unavailable }
        return projection
    }
    private func replay<P: Encodable>(_ id: UUID, _ args: P) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(args)
        if let previous = receipts[id] {
            guard previous == bytes else { throw TeacherPromptError.mutationReused }
            return true
        }
        return false
    }
    private func record<P: Encodable>(_ id: UUID, _ args: P) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        receipts[id] = try encoder.encode(args)
    }
    private func editable(_ id: UUID, revision: String) throws {
        guard id == Self.lessonID else { throw TeacherPromptError.unavailable }
        guard projection.lesson.can_edit else { throw TeacherPromptError.locked }
        guard projection.lesson.register_revision == revision else { throw TeacherPromptError.conflict }
    }
    private func bump() {
        projection.lesson.register_revision = String((Int(projection.lesson.register_revision) ?? 0) + 1)
        projection.lesson.marked_count = projection.roster.filter { $0.status != nil }.count
        projection.lesson.can_submit = projection.lesson.marked_count == projection.roster.count
    }
    func allPresent(_ m: TeacherRegisterMutation) async throws {
        if try replay(m.p_mutation_id, m) { return }
        try editable(m.p_lesson_id, revision: m.p_expected_revision)
        var changed = false
        for i in projection.roster.indices where projection.roster[i].status == nil {
            projection.roster[i].status = .present; projection.roster[i].marked_at = instant; changed = true
        }
        if changed { bump() }
        try record(m.p_mutation_id, m)
    }
    func mark(_ m: TeacherMark) async throws {
        if try replay(m.p_mutation_id, m) { return }
        try editable(m.p_lesson_id, revision: m.p_expected_revision)
        guard let i = projection.roster.firstIndex(where: { $0.id == m.p_student_id }) else { throw TeacherPromptError.invalid }
        guard projection.roster[i].marked_at == m.p_observed_marked_at else { throw TeacherPromptError.conflict }
        projection.roster[i].status = m.p_status
        projection.roster[i].absence_informed = m.p_status == .absent ? m.p_absence_informed : nil
        projection.roster[i].marked_at = m.p_status == nil ? nil : instant
        bump(); try record(m.p_mutation_id, m)
    }
    func feedback(_ m: TeacherFeedbackMutation) async throws {
        if try replay(m.p_mutation_id, m) { return }
        try editable(m.p_lesson_id, revision: projection.lesson.register_revision)
        guard m.p_expected_feedback_revision == projection.feedback.revision else { throw TeacherPromptError.conflict }
        guard m.p_body.unicodeScalars.count <= 1000,
              m.p_body.range(of: "[STFGM][0-9]{7}[A-Z]", options: [.regularExpression, .caseInsensitive]) == nil else { throw TeacherPromptError.invalid }
        projection.feedback = TeacherLessonFeedback(body: m.p_body.trimmingCharacters(in: .whitespacesAndNewlines),
            revision: String((Int(projection.feedback.revision) ?? 0) + 1))
        try record(m.p_mutation_id, m)
    }
    func submit(_ m: TeacherSubmitMutation) async throws {
        if try replay(m.p_mutation_id, m) { return }
        try editable(m.p_lesson_id, revision: m.p_expected_revision)
        guard projection.feedback.revision == m.p_expected_feedback_revision else { throw TeacherPromptError.conflict }
        guard projection.roster.allSatisfy({ $0.status != nil }) else { throw TeacherPromptError.incomplete }
        projection.submission = TeacherLessonSubmission(id: m.p_mutation_id, submitted_at: instant,
            submitted_by: accountID, register_revision: projection.lesson.register_revision)
        projection.lesson.state = "submitted"; projection.lesson.submitted_at = instant
        projection.lesson.can_edit = false; projection.lesson.can_submit = false; projection.lesson.can_snooze = false
        projection.lesson.next_prompt_at = nil
        try record(m.p_mutation_id, m)
    }
    func snooze(_ lessonID: UUID, mutationID: UUID) async throws {
        if try replay(mutationID, lessonID) { return }
        try editable(lessonID, revision: projection.lesson.register_revision)
        guard snoozeCount < 3 else { throw TeacherPromptError.snoozeLimit }
        guard projection.lesson.can_snooze else { throw TeacherPromptError.noPrompt }
        snoozeCount += 1
        projection.lesson.can_snooze = snoozeCount < 3
        projection.lesson.snoozed_until = "2027-01-07T13:\(String(format: "%02d", 5 + 10 * snoozeCount)):00Z"
        try record(mutationID, lessonID)
    }
}

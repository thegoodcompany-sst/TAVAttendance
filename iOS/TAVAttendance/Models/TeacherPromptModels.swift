import Foundation
import PromptRouter

// Wire keys deliberately match the v2 JSON projections. Keep timestamps as strings:
// round-tripping a Date would discard the microseconds required by attendance CAS.
enum TeacherAttendanceStatus: String, Codable, CaseIterable {
    case present, late, absent
    var label: String {
        switch self {
        case .present: return PromptStrings.present
        case .late: return PromptStrings.late
        case .absent: return PromptStrings.absent
        }
    }
}
struct TeacherLessonSummary: Codable, Identifiable {
    var lesson_id: UUID
    var class_id: UUID
    var class_label: String
    var scheduled_start_at: String
    var scheduled_end_at: String
    var state: String
    var accountable_teacher_id: UUID
    var accountable_teacher_label: String
    var is_accountable: Bool
    var register_revision: String
    var roster_count: Int
    var marked_count: Int
    var submitted_at: String?
    var next_prompt_at: String?
    var snoozed_until: String?
    var overdue_at: String
    var can_edit: Bool
    var can_submit: Bool
    var can_snooze: Bool
    var id: UUID { lesson_id }
}
struct TeacherRosterStudent: Codable, Identifiable {
    var student_id: UUID
    var display_name: String
    var status: TeacherAttendanceStatus?
    var absence_informed: Bool?
    var marked_at: String?
    var id: UUID { student_id }
}
struct TeacherLessonFeedback: Codable { var body: String; var revision: String }
struct TeacherLessonSubmission: Codable {
    let id: UUID
    let submitted_at: String
    let submitted_by: UUID
    let register_revision: String
}
struct TeacherLessonProjection: Codable {
    var server_now: String
    var lesson: TeacherLessonSummary
    var roster: [TeacherRosterStudent]
    var feedback: TeacherLessonFeedback
    var submission: TeacherLessonSubmission?
}
struct TeacherLessons: Codable {
    let server_now: String
    let date: String
    var lessons: [TeacherLessonSummary]
    var outstanding_count: Int
    var backlog: [TeacherLessonSummary]
}
struct TeacherProfile: Decodable {
    let id: UUID
    let display_name: String
    let role: String
    let active: Bool
}
struct TeacherMark: Encodable, Equatable {
    let p_lesson_id: UUID
    let p_student_id: UUID
    let p_status: TeacherAttendanceStatus?
    let p_absence_informed: Bool?
    let p_observed_marked_at: String?
    let p_expected_revision: String
    let p_mutation_id: UUID

    // PostgREST needs explicit JSON null for required nullable parameters.
    enum CodingKeys: String, CodingKey {
        case p_lesson_id, p_student_id, p_status, p_absence_informed
        case p_observed_marked_at, p_expected_revision, p_mutation_id
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_lesson_id, forKey: .p_lesson_id)
        try c.encode(p_student_id, forKey: .p_student_id)
        try c.encode(p_status, forKey: .p_status)
        try c.encode(p_absence_informed, forKey: .p_absence_informed)
        try c.encode(p_observed_marked_at, forKey: .p_observed_marked_at)
        try c.encode(p_expected_revision, forKey: .p_expected_revision)
        try c.encode(p_mutation_id, forKey: .p_mutation_id)
    }
}
struct TeacherRegisterMutation: Encodable, Equatable {
    let p_lesson_id: UUID
    let p_expected_revision: String
    let p_mutation_id: UUID
}
struct TeacherFeedbackMutation: Encodable, Equatable {
    let p_lesson_id: UUID
    let p_body: String
    let p_expected_feedback_revision: String
    let p_mutation_id: UUID
}
struct TeacherSubmitMutation: Encodable, Equatable {
    let p_lesson_id: UUID
    let p_expected_revision: String
    let p_expected_feedback_revision: String
    let p_mutation_id: UUID
}
struct TeacherMarkReceipt: Decodable {
    let lesson_id: UUID
    let student_id: UUID
    let status: TeacherAttendanceStatus?
    let absence_informed: Bool?
    let marked_at: String?
    let register_revision: String
    let replayed: Bool
}
struct TeacherAllPresentReceipt: Decodable {
    let lesson_id: UUID
    let changed_count: Int
    let register_revision: String
    let replayed: Bool
}
struct TeacherFeedbackReceipt: Decodable {
    let lesson_id: UUID
    let feedback_revision: String
    let replayed: Bool
}
struct TeacherSubmitReceipt: Decodable {
    let lesson_id: UUID
    let submission_id: UUID
    let submitted_at: String
    let register_revision: String
    let replayed: Bool
}
struct TeacherSnoozeReceipt: Decodable {
    let lesson_id: UUID
    let snoozed_until: String
    let next_prompt_at: String?
    let overdue_at: String
    let replayed: Bool
}

enum TeacherPromptError: String, Error, CaseIterable {
    case disabled = "TP_DISABLED", unavailable = "TP_NOT_AVAILABLE", conflict = "TP_CONFLICT"
    case incomplete = "TP_INCOMPLETE", locked = "TP_LOCKED", tooEarly = "TP_TOO_EARLY"
    case tooOld = "TP_TOO_OLD", snoozeLimit = "TP_SNOOZE_LIMIT", noPrompt = "TP_NO_PENDING_PROMPT"
    case mutationReused = "TP_MUTATION_REUSED", invalid = "TP_INVALID_INPUT"
    case sessionExpired, network
    var message: String {
        switch self {
        case .disabled: return PromptStrings.disabled
        case .unavailable: return PromptStrings.unavailable
        case .conflict: return PromptStrings.stale
        case .incomplete: return PromptStrings.incomplete
        case .locked: return PromptStrings.readOnly
        case .tooEarly: return PromptStrings.tooEarly
        case .tooOld: return PromptStrings.tooOld
        case .snoozeLimit: return PromptStrings.snoozeLimit
        case .noPrompt: return PromptStrings.noPrompt
        case .mutationReused: return PromptStrings.refreshLesson
        case .invalid: return PromptStrings.invalid
        case .sessionExpired: return PromptStrings.signIn
        case .network: return PromptStrings.networkError
        }
    }
}

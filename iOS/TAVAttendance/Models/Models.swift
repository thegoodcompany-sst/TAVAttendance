import Foundation

// MARK: - Result slip subject (only Math and English in v1)
enum ResultSlipSubject: String, Codable, CaseIterable, Identifiable {
    case math    = "Math"
    case english = "English"
    var id: String { rawValue }
}

struct Profile: Codable, Identifiable {
    let id: UUID
    let fullName: String
    let role: String
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, role
        case fullName = "full_name"
    }
}

struct TAVClass: Codable, Identifiable {
    let id: UUID
    let name: String
    let subject: String?
    let level: String?
    let scheduleDay: String?
    let scheduleTime: String?
    let durationMinutes: Int
    let isActive: Bool
    let recurrenceRule: String?      // RFC 5545 RRULE, e.g. "FREQ=WEEKLY;BYDAY=MO"
    let recurrenceEndDate: String?   // "yyyy-MM-dd", nil = open-ended

    enum CodingKeys: String, CodingKey {
        case id, name, subject, level
        case scheduleDay        = "schedule_day"
        case scheduleTime       = "schedule_time"
        case durationMinutes    = "duration_minutes"
        case isActive           = "is_active"
        case recurrenceRule     = "recurrence_rule"
        case recurrenceEndDate  = "recurrence_end_date"
    }
}

struct Student: Codable, Identifiable {
    let id: UUID
    let fullName: String
    let school: String?
    let yearOfStudy: String?
    let isActive: Bool
    // PROD-04: storage path to the student's photo in the `student-photos` bucket.
    // nil until uploaded; only shown when the `student_photos` feature flag is on.
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, school
        case fullName    = "full_name"
        case yearOfStudy = "year_of_study"
        case isActive    = "is_active"
        case avatarUrl   = "avatar_url"
    }
}

struct Session: Codable, Identifiable, Hashable {
    let id: UUID
    let classId: UUID
    let sessionDate: String
    let topic: String?
    let notes: String?
    let startedAt: Date?
    let endedAt: Date?      // set when tutor ends the class; nil while in progress
    let subTutorId: UUID?   // per-session substitute tutor

    enum CodingKeys: String, CodingKey {
        case id, topic, notes
        case classId     = "class_id"
        case sessionDate = "session_date"
        case startedAt   = "started_at"
        case endedAt     = "ended_at"
        case subTutorId  = "sub_tutor_id"
    }
}

enum AttendanceStatus: String, Codable, CaseIterable {
    case present, absent, late, excused
}

struct AttendanceRecord: Codable, Identifiable {
    let id: UUID?
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    let markedBy: UUID?
    let markedAt: Date?
    var notes: String?
    var lateReason: String?
    let clientMutationId: String

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case sessionId        = "session_id"
        case studentId        = "student_id"
        case markedBy         = "marked_by"
        case markedAt         = "marked_at"
        case lateReason       = "late_reason"
        case clientMutationId = "client_mutation_id"
    }
}

struct AttendanceInsert: Encodable {
    let sessionId: UUID
    let studentId: UUID
    let status: AttendanceStatus
    let notes: String?
    let lateReason: String?
    let clientMutationId: String

    enum CodingKeys: String, CodingKey {
        case status, notes
        case sessionId        = "session_id"
        case studentId        = "student_id"
        case lateReason       = "late_reason"
        case clientMutationId = "client_mutation_id"
    }
}

struct RosterEntry: Codable, Identifiable {
    let studentId: UUID
    let fullName: String
    let attendanceId: UUID?
    var status: AttendanceStatus?
    let markedAt: Date?
    var notes: String?
    var lateReason: String?
    let avatarUrl: String?   // PROD-04; nil unless a photo was uploaded

    var id: UUID { studentId }

    enum CodingKeys: String, CodingKey {
        case status, notes
        case studentId    = "student_id"
        case fullName     = "full_name"
        case attendanceId = "attendance_id"
        case markedAt     = "marked_at"
        case lateReason   = "late_reason"
        case avatarUrl    = "avatar_url"
    }
}

// MARK: - Admin insert types (no server-assigned fields)

struct ClassInsert: Encodable {
    let name: String
    let subject: String?
    let level: String?
    let scheduleDay: String?
    let scheduleTime: String?
    let durationMinutes: Int
    let isActive: Bool
    let recurrenceRule: String?
    let recurrenceEndDate: String?

    enum CodingKeys: String, CodingKey {
        case name, subject, level
        case scheduleDay        = "schedule_day"
        case scheduleTime       = "schedule_time"
        case durationMinutes    = "duration_minutes"
        case isActive           = "is_active"
        case recurrenceRule     = "recurrence_rule"
        case recurrenceEndDate  = "recurrence_end_date"
    }
}

struct StudentInsert: Encodable {
    let fullName: String
    let school: String?
    let yearOfStudy: String?

    enum CodingKeys: String, CodingKey {
        case fullName    = "full_name"
        case school
        case yearOfStudy = "year_of_study"
    }
}

struct Enrollment: Codable, Identifiable {
    let id: UUID
    let studentId: UUID
    let classId: UUID
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case studentId = "student_id"
        case classId   = "class_id"
        case isActive  = "is_active"
    }
}

struct TutorAssignment: Codable, Identifiable {
    let id: UUID
    let classId: UUID
    let tutorId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case classId = "class_id"
        case tutorId = "tutor_id"
    }
}

// One session slot inside a KioskEntry — carries the class schedule time for auto-late detection
struct KioskSession {
    let id: UUID
    let scheduleTime: String?  // "HH:mm" as stored in classes.schedule_time, nil if unset
    let startedAt: Date?       // set when teacher taps "Start Class"; takes priority over scheduleTime
}

// Used by the global kiosk — one entry per unique student across all today's sessions
struct KioskEntry: Identifiable {
    let studentId: UUID
    let fullName: String
    var status: AttendanceStatus?   // nil = not yet marked today
    var sessions: [KioskSession]
    var markedAt: Date?             // device-local time of the most recent marking this session
    var dismissedAt: Date?          // set when admin marks student as dismissed; attendance status unchanged
    var lateReason: String?         // admin-entered reason for late arrival
    var avatarUrl: String?          // PROD-04; storage path, shown when student_photos flag is on
    var id: UUID { studentId }

    // Attending = physically present, whether on time or late (excludes absent/excused)
    var isAttending: Bool { status == .present || status == .late }

    // Dismissed = attended AND has been signed out by admin
    var isDismissed: Bool { dismissedAt != nil }
}

// MARK: - Dismissal

struct Dismissal: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let studentId: UUID
    let dismissedAt: Date?
    let dismissedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId   = "session_id"
        case studentId   = "student_id"
        case dismissedAt = "dismissed_at"
        case dismissedBy = "dismissed_by"
    }
}

// MARK: - Punctuality summary

struct PunctualitySummary: Codable {
    let presentCount: Int
    let lateCount: Int
    let absentCount: Int
    let excusedCount: Int
    let totalCount: Int
    let onTimeRate: Double?   // 0.0–1.0, nil when totalCount == 0

    enum CodingKeys: String, CodingKey {
        case presentCount = "present_count"
        case lateCount    = "late_count"
        case absentCount  = "absent_count"
        case excusedCount = "excused_count"
        case totalCount   = "total_count"
        case onTimeRate   = "on_time_rate"
    }
}

// MARK: - Result slip

struct ResultSlip: Codable, Identifiable {
    let id: UUID
    let studentId: UUID
    let examName: String?
    let examDate: String?     // "yyyy-MM-dd"
    let subject: String?      // "Math" or "English"
    let score: Double?
    let maxScore: Double?
    let filePath: String?     // Supabase Storage object path
    let uploadedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case studentId  = "student_id"
        case examName   = "exam_name"
        case examDate   = "exam_date"
        case subject
        case score
        case maxScore   = "max_score"
        case filePath   = "file_path"
        case uploadedAt = "uploaded_at"
    }

    // Fraction string for display, e.g. "25 / 35"
    var fractionDisplay: String? {
        guard let s = score, let m = maxScore else { return nil }
        let sInt = s == s.rounded() ? String(Int(s)) : String(s)
        let mInt = m == m.rounded() ? String(Int(m)) : String(m)
        return "\(sInt) / \(mInt)"
    }

    var percentageDisplay: String? {
        guard let s = score, let m = maxScore, m > 0 else { return nil }
        return "\(Int((s / m * 100).rounded()))%"
    }
}

// MARK: - PDPA: policy documents (privacy notice)

struct PolicyDocument: Codable, Identifiable {
    let id: UUID
    let docType: String
    let version: String
    let title: String
    let body: String
    let isCurrent: Bool
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, version, title, body
        case docType     = "doc_type"
        case isCurrent   = "is_current"
        case publishedAt = "published_at"
    }
}

// MARK: - PDPA: consent ledger

enum ConsentStatus: String, Codable {
    case granted
    case withdrawn
}

/// Latest consent row per (student_id, consent_type) — decoded from `current_consent` view.
struct ConsentRecord: Codable, Identifiable {
    let studentId: UUID
    let consentType: String
    let status: ConsentStatus
    let method: String
    let noticeVersion: String?
    let grantedBy: UUID?
    let parentId: UUID?
    let createdAt: Date?

    // current_consent has no id column; use the (student, type) pair as identity.
    var id: String { "\(studentId.uuidString)-\(consentType)" }

    enum CodingKeys: String, CodingKey {
        case status, method
        case studentId     = "student_id"
        case consentType   = "consent_type"
        case noticeVersion = "notice_version"
        case grantedBy     = "granted_by"
        case parentId      = "parent_id"
        case createdAt     = "created_at"
    }
}

// MARK: - PDPA: correction requests

enum CorrectionStatus: String, Codable {
    case pending, applied, rejected
}

struct CorrectionRequest: Codable, Identifiable {
    let id: UUID
    let studentId: UUID
    let requestedBy: UUID?
    let fieldName: String
    let currentValue: String?
    let requestedValue: String?
    let status: CorrectionStatus
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let reviewNote: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case studentId      = "student_id"
        case requestedBy    = "requested_by"
        case fieldName      = "field_name"
        case currentValue   = "current_value"
        case requestedValue = "requested_value"
        case reviewedBy     = "reviewed_by"
        case reviewedAt     = "reviewed_at"
        case reviewNote     = "review_note"
        case createdAt      = "created_at"
    }
}

// Fetched with a PostgREST join for the student profile history sheet
struct AttendanceHistoryRecord: Codable, Identifiable {
    let id: UUID
    let status: AttendanceStatus
    let markedAt: Date?
    let session: SessionSummary

    struct SessionSummary: Codable {
        let sessionDate: String
        let `class`: ClassSummary

        struct ClassSummary: Codable {
            let name: String
        }

        enum CodingKeys: String, CodingKey {
            case sessionDate = "session_date"
            case `class` = "class"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case markedAt = "marked_at"
        case session
    }
}

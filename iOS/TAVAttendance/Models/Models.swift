import Foundation

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

    enum CodingKeys: String, CodingKey {
        case id, name, subject, level
        case scheduleDay     = "schedule_day"
        case scheduleTime    = "schedule_time"
        case durationMinutes = "duration_minutes"
        case isActive        = "is_active"
    }
}

struct Student: Codable, Identifiable {
    let id: UUID
    let fullName: String
    let school: String?
    let yearOfStudy: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, school
        case fullName    = "full_name"
        case yearOfStudy = "year_of_study"
        case isActive    = "is_active"
    }
}

struct Session: Codable, Identifiable, Hashable {
    let id: UUID
    let classId: UUID
    let sessionDate: String
    let topic: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, topic, notes
        case classId     = "class_id"
        case sessionDate = "session_date"
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
    let clientMutationId: String

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case sessionId        = "session_id"
        case studentId        = "student_id"
        case markedBy         = "marked_by"
        case markedAt         = "marked_at"
        case clientMutationId = "client_mutation_id"
    }
}

struct AttendanceInsert: Encodable {
    let sessionId: UUID
    let studentId: UUID
    let status: AttendanceStatus
    let notes: String?
    let clientMutationId: String

    enum CodingKeys: String, CodingKey {
        case status, notes
        case sessionId        = "session_id"
        case studentId        = "student_id"
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

    var id: UUID { studentId }

    enum CodingKeys: String, CodingKey {
        case status, notes
        case studentId    = "student_id"
        case fullName     = "full_name"
        case attendanceId = "attendance_id"
        case markedAt     = "marked_at"
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

    enum CodingKeys: String, CodingKey {
        case name, subject, level
        case scheduleDay     = "schedule_day"
        case scheduleTime    = "schedule_time"
        case durationMinutes = "duration_minutes"
        case isActive        = "is_active"
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
}

// Used by the global kiosk — one entry per unique student across all today's sessions
struct KioskEntry: Identifiable {
    let studentId: UUID
    let fullName: String
    var status: AttendanceStatus?   // nil = not yet marked today
    var sessions: [KioskSession]
    var markedAt: Date?             // device-local time of the most recent marking this session
    var id: UUID { studentId }

    // Attending = physically present, whether on time or late (excludes absent/excused)
    var isAttending: Bool { status == .present || status == .late }
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

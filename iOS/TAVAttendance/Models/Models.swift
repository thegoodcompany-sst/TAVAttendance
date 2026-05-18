import Foundation

// MARK: - Profile

struct Profile: Codable, Identifiable {
    let id: UUID
    let fullName: String
    let role: UserRole
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, role
        case fullName = "full_name"
    }
}

enum UserRole: String, Codable, Hashable, Equatable {
    case admin, tutor, parent
}

// MARK: - Class

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

// MARK: - Student

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

// MARK: - Session

struct TAVSession: Codable, Identifiable {
    let id: UUID
    let classId: UUID
    let sessionDate: String   // "YYYY-MM-DD"
    let topic: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, topic, notes
        case classId     = "class_id"
        case sessionDate = "session_date"
    }
}

// MARK: - Attendance

enum AttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case present, absent, late, excused

    var id: String { rawValue }

    var label: String {
        switch self {
        case .present: return "Present"
        case .absent:  return "Absent"
        case .late:    return "Late"
        case .excused: return "Excused"
        }
    }

    var shortLabel: String {
        switch self {
        case .present: return "P"
        case .absent:  return "A"
        case .late:    return "L"
        case .excused: return "E"
        }
    }
}

struct AttendanceRecord: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let studentId: UUID
    let status: AttendanceStatus
    let markedBy: UUID?
    let markedAt: Date?
    let notes: String?
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

// Sent to Supabase on upsert — omits server-assigned id.
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

// MARK: - Roster (from get_session_roster RPC)

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

// MARK: - Offline Pending Record

struct PendingAttendanceRecord: Codable, Identifiable {
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    var notes: String?
    let clientMutationId: String
    let markedAt: Date
    var isSynced: Bool

    var id: String { clientMutationId }
}

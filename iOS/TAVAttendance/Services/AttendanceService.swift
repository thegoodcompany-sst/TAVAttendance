import Foundation
import Supabase

final class AttendanceService {
    static let shared = AttendanceService()
    private let db = SupabaseManager.shared.client

    // MARK: - Classes

    func fetchMyClasses() async throws -> [TAVClass] {
        return try await db
            .from("classes").select()
            .eq("is_active", value: true).order("name")
            .execute().value
    }

    func createClass(_ cls: ClassInsert) async throws -> TAVClass {
        return try await db.from("classes").insert(cls).select().single().execute().value
    }

    func updateClass(id: UUID, _ cls: ClassInsert) async throws {
        try await db.from("classes").update(cls).eq("id", value: id).execute()
    }

    func deleteClass(id: UUID) async throws {
        try await db.from("classes").update(["is_active": false]).eq("id", value: id).execute()
    }

    // MARK: - Students

    func fetchAllStudents() async throws -> [Student] {
        return try await db.from("students").select()
            .eq("is_active", value: true).order("full_name")
            .execute().value
    }

    func createStudent(_ student: StudentInsert) async throws -> Student {
        return try await db.from("students").insert(student).select().single().execute().value
    }

    func updateStudent(id: UUID, _ student: StudentInsert) async throws {
        try await db.from("students").update(student).eq("id", value: id).execute()
    }

    func deactivateStudent(id: UUID) async throws {
        try await db.from("students").update(["is_active": false]).eq("id", value: id).execute()
    }

    // MARK: - Enrollments

    func fetchEnrollments(classId: UUID) async throws -> [Enrollment] {
        return try await db.from("enrollments").select()
            .eq("class_id", value: classId).eq("is_active", value: true)
            .execute().value
    }

    func enrollStudent(studentId: UUID, classId: UUID) async throws {
        struct EnrollInsert: Encodable {
            let studentId: UUID; let classId: UUID; let isActive: Bool
            enum CodingKeys: String, CodingKey {
                case studentId = "student_id"; case classId = "class_id"; case isActive = "is_active"
            }
        }
        try await db.from("enrollments")
            .upsert(EnrollInsert(studentId: studentId, classId: classId, isActive: true),
                    onConflict: "student_id,class_id")
            .execute()
    }

    func unenrollStudent(studentId: UUID, classId: UUID) async throws {
        try await db.from("enrollments")
            .update(["is_active": false])
            .eq("student_id", value: studentId).eq("class_id", value: classId)
            .execute()
    }

    // MARK: - Tutor assignments

    func fetchTutors() async throws -> [Profile] {
        return try await db.from("profiles").select()
            .eq("role", value: "tutor").order("full_name")
            .execute().value
    }

    func fetchTutorAssignments(classId: UUID) async throws -> [TutorAssignment] {
        return try await db.from("class_tutor_assignments")
            .select("id, class_id, tutor_id")
            .eq("class_id", value: classId)
            .execute().value
    }

    func assignTutor(tutorId: UUID, classId: UUID) async throws {
        struct AssignInsert: Encodable {
            let classId: UUID; let tutorId: UUID
            enum CodingKeys: String, CodingKey {
                case classId = "class_id"; case tutorId = "tutor_id"
            }
        }
        try await db.from("class_tutor_assignments")
            .upsert(AssignInsert(classId: classId, tutorId: tutorId), onConflict: "class_id,tutor_id")
            .execute()
    }

    func unassignTutor(tutorId: UUID, classId: UUID) async throws {
        try await db.from("class_tutor_assignments")
            .delete()
            .eq("class_id", value: classId).eq("tutor_id", value: tutorId)
            .execute()
    }

    // MARK: - Sessions

    func fetchSessions(for classId: UUID) async throws -> [Session] {
        return try await db.from("sessions").select()
            .eq("class_id", value: classId).order("session_date", ascending: false)
            .execute().value
    }

    func getOrCreateSession(classId: UUID, date: String) async throws -> Session {
        let existing: [Session] = try await db.from("sessions").select()
            .eq("class_id", value: classId).eq("session_date", value: date)
            .execute().value
        if let session = existing.first { return session }
        let new = Session(id: UUID(), classId: classId, sessionDate: date, topic: nil, notes: nil)
        return try await db.from("sessions").insert(new).select().single().execute().value
    }

    // MARK: - Roster & Attendance

    func fetchRoster(sessionId: UUID) async throws -> [RosterEntry] {
        return try await db
            .rpc("get_session_roster", params: ["p_session_id": sessionId.uuidString])
            .execute().value
    }

    func markAttendance(sessionId: UUID, studentId: UUID, status: AttendanceStatus, notes: String? = nil) async throws {
        let record = AttendanceInsert(
            sessionId: sessionId, studentId: studentId, status: status,
            notes: notes, clientMutationId: UUID().uuidString)
        try await db.from("attendance_records")
            .upsert(record, onConflict: "session_id,student_id").execute()
    }

    func syncPending(_ records: [PendingAttendanceRecord]) async throws -> (synced: Int, skipped: Int) {
        let payload = records.map { r -> [String: String] in
            ["session_id": r.sessionId.uuidString, "student_id": r.studentId.uuidString,
             "status": r.status.rawValue, "notes": r.notes ?? "",
             "client_mutation_id": r.clientMutationId,
             "marked_at": ISO8601DateFormatter().string(from: r.markedAt)]
        }
        let result: [String: Int] = try await db
            .rpc("sync_attendance", params: ["records": payload]).execute().value
        return (result["synced"] ?? 0, result["skipped"] ?? 0)
    }
}

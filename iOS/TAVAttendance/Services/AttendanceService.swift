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

    // MARK: - Global kiosk

    func fetchKioskEntries() async throws -> [KioskEntry] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let classes = try await fetchMyClasses()
        let classMap = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })

        var sessionPairs: [(classId: UUID, sessionId: UUID)] = []
        for cls in classes {
            let session = try await getOrCreateSession(classId: cls.id, date: today)
            sessionPairs.append((cls.id, session.id))
        }

        var entryMap: [UUID: KioskEntry] = [:]
        try await withThrowingTaskGroup(of: (UUID, UUID, [RosterEntry]).self) { group in
            for (classId, sessionId) in sessionPairs {
                group.addTask { (classId, sessionId, try await self.fetchRoster(sessionId: sessionId)) }
            }
            for try await (classId, sessionId, roster) in group {
                let scheduleTime = classMap[classId]?.scheduleTime
                let slot = KioskSession(id: sessionId, scheduleTime: scheduleTime)
                for r in roster {
                    if var existing = entryMap[r.studentId] {
                        existing.sessions.append(slot)
                        existing.status = Self.worstStatus(existing.status, r.status)
                        if let t = r.markedAt, (existing.markedAt == nil || t > existing.markedAt!) {
                            existing.markedAt = t
                        }
                        entryMap[r.studentId] = existing
                    } else {
                        entryMap[r.studentId] = KioskEntry(
                            studentId: r.studentId, fullName: r.fullName,
                            status: r.status, sessions: [slot], markedAt: r.markedAt)
                    }
                }
            }
        }
        return Array(entryMap.values).sorted { $0.fullName < $1.fullName }
    }

    // late > present > absent > excused — worst shown when a student spans multiple sessions
    private static func worstStatus(_ a: AttendanceStatus?, _ b: AttendanceStatus?) -> AttendanceStatus? {
        let rank: [AttendanceStatus: Int] = [.late: 4, .present: 3, .absent: 2, .excused: 1]
        switch (a, b) {
        case (nil, let x): return x
        case (let x, nil): return x
        case (let x?, let y?): return (rank[y] ?? 0) > (rank[x] ?? 0) ? y : x
        }
    }

    /// Marks a student across all their today's sessions. Status is applied as-is to every session.
    func markKioskAttendance(entry: KioskEntry, status: AttendanceStatus) async throws {
        for session in entry.sessions {
            try await markAttendance(sessionId: session.id, studentId: entry.studentId, status: status)
        }
    }

    /// Marks each session independently: late if the class has already started, present otherwise.
    func markKioskSignIn(entry: KioskEntry) async throws {
        let cal = Calendar.current
        let now = Date()
        var todayComponents = cal.dateComponents([.year, .month, .day], from: now)

        for session in entry.sessions {
            var status: AttendanceStatus = .present
            if let timeStr = session.scheduleTime {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                if parts.count >= 2 {
                    todayComponents.hour = parts[0]
                    todayComponents.minute = parts[1]
                    todayComponents.second = 0
                    if let classStart = cal.date(from: todayComponents), now > classStart {
                        status = .late
                    }
                }
            }
            try await markAttendance(sessionId: session.id, studentId: entry.studentId, status: status)
        }
    }

    /// Fetches a student's recent attendance history with class name, for the profile sheet.
    func fetchStudentAttendanceHistory(studentId: UUID, limit: Int = 20) async throws -> [AttendanceHistoryRecord] {
        return try await db
            .from("attendance_records")
            .select("id, status, marked_at, session:sessions(session_date, class:classes(name))")
            .eq("student_id", value: studentId)
            .order("marked_at", ascending: false)
            .limit(limit)
            .execute()
            .value
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

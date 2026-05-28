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
        let new = Session(id: UUID(), classId: classId, sessionDate: date, topic: nil, notes: nil, startedAt: nil, subTutorId: nil)
        return try await db.from("sessions").insert(new).select().single().execute().value
    }

    /// Sets started_at = NOW(). Re-tapping "Start Class" updates the start time (useful if tapped early).
    func startSession(id: UUID) async throws {
        struct Patch: Encodable {
            let startedAt: Date
            enum CodingKeys: String, CodingKey { case startedAt = "started_at" }
        }
        try await db.from("sessions")
            .update(Patch(startedAt: Date()))
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Roster & Attendance

    func fetchRoster(sessionId: UUID) async throws -> [RosterEntry] {
        return try await db
            .rpc("get_session_roster", params: ["p_session_id": sessionId.uuidString])
            .execute().value
    }

    func markAttendance(sessionId: UUID, studentId: UUID, status: AttendanceStatus, notes: String? = nil, lateReason: String? = nil) async throws {
        let record = AttendanceInsert(
            sessionId: sessionId, studentId: studentId, status: status,
            notes: notes, lateReason: lateReason, clientMutationId: UUID().uuidString)
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

        var sessionTuples: [(classId: UUID, session: Session)] = []
        for cls in classes {
            let session = try await getOrCreateSession(classId: cls.id, date: today)
            sessionTuples.append((cls.id, session))
        }

        var entryMap: [UUID: KioskEntry] = [:]
        try await withThrowingTaskGroup(of: (UUID, Session, [RosterEntry]).self) { group in
            for (classId, session) in sessionTuples {
                group.addTask { (classId, session, try await self.fetchRoster(sessionId: session.id)) }
            }
            for try await (classId, session, roster) in group {
                let scheduleTime = classMap[classId]?.scheduleTime
                let slot = KioskSession(id: session.id, scheduleTime: scheduleTime, startedAt: session.startedAt)
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
    func markKioskAttendance(entry: KioskEntry, status: AttendanceStatus, lateReason: String? = nil) async throws {
        for session in entry.sessions {
            try await markAttendance(sessionId: session.id, studentId: entry.studentId, status: status, lateReason: lateReason)
        }
    }

    /// Marks each session independently: late if the class has already started, present otherwise.
    func markKioskSignIn(entry: KioskEntry) async throws {
        let cal = Calendar.current
        let now = Date()
        var todayComponents = cal.dateComponents([.year, .month, .day], from: now)

        for session in entry.sessions {
            var status: AttendanceStatus = .present

            // If teacher manually started the class, everyone signing in now is Late
            if let startedAt = session.startedAt, now > startedAt {
                status = .late
            } else if let timeStr = session.scheduleTime {
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
    func fetchStudentAttendanceHistory(studentId: UUID, limit: Int = 100, since: Date? = nil) async throws -> [AttendanceHistoryRecord] {
        var filterBuilder = db
            .from("attendance_records")
            .select("id, status, marked_at, session:sessions(session_date, class:classes(name))")
            .eq("student_id", value: studentId)

        if let since {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            filterBuilder = filterBuilder.gte("marked_at", value: iso.string(from: since))
        }

        return try await filterBuilder
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

    // MARK: - Dismissals (#15)

    func recordDismissal(sessionId: UUID, studentId: UUID) async throws -> Dismissal {
        struct DismissalInsert: Encodable {
            let sessionId: UUID; let studentId: UUID; let dismissedAt: Date
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"; case studentId = "student_id"; case dismissedAt = "dismissed_at"
            }
        }
        return try await db.from("dismissals")
            .insert(DismissalInsert(sessionId: sessionId, studentId: studentId, dismissedAt: Date()))
            .select().single().execute().value
    }

    func undoDismissal(sessionId: UUID, studentId: UUID) async throws {
        try await db.from("dismissals")
            .delete()
            .eq("session_id", value: sessionId)
            .eq("student_id", value: studentId)
            .execute()
    }

    /// Returns a map of studentId → Dismissal for the given students across today's sessions.
    func fetchTodaysDismissals(sessionIds: [UUID]) async throws -> [UUID: Dismissal] {
        guard !sessionIds.isEmpty else { return [:] }
        let rows: [Dismissal] = try await db.from("dismissals")
            .select()
            .in("session_id", values: sessionIds.map(\.uuidString))
            .execute().value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.studentId, $0) })
    }

    // MARK: - Punctuality (#8)

    func fetchClassPunctuality(classId: UUID, from: Date, to: Date) async throws -> PunctualitySummary {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let rows: [PunctualitySummary] = try await db
            .rpc("class_punctuality", params: [
                "p_class_id": classId.uuidString,
                "p_from": iso.string(from: from),
                "p_to": iso.string(from: to)
            ])
            .execute().value
        return rows.first ?? PunctualitySummary(
            presentCount: 0, lateCount: 0, absentCount: 0,
            excusedCount: 0, totalCount: 0, onTimeRate: nil)
    }

    // MARK: - Bulk student import (#12)

    func bulkCreateStudents(_ rows: [StudentInsert]) async throws -> [Student] {
        return try await db.from("students").insert(rows).select().execute().value
    }

    // MARK: - Substitution (#16)

    func setSessionSubstitute(sessionId: UUID, tutorId: UUID?) async throws {
        struct Patch: Encodable {
            let subTutorId: UUID?
            enum CodingKeys: String, CodingKey { case subTutorId = "sub_tutor_id" }
        }
        try await db.from("sessions")
            .update(Patch(subTutorId: tutorId))
            .eq("id", value: sessionId)
            .execute()
    }

    // MARK: - Result slips (#20)

    func uploadResultSlip(
        studentId: UUID,
        fileData: Data,
        fileName: String,
        mime: String,
        examName: String?,
        examDate: Date?,
        subject: String?,
        score: Double?,
        maxScore: Double?
    ) async throws -> ResultSlip {
        let path = "\(studentId.uuidString)/\(UUID().uuidString)-\(fileName)"
        try await db.storage.from("result-slips")
            .upload(path: path, file: fileData, options: .init(contentType: mime, upsert: false))

        struct SlipInsert: Encodable {
            let studentId: UUID; let examName: String?; let examDate: String?
            let subject: String?; let score: Double?; let maxScore: Double?; let filePath: String
            enum CodingKeys: String, CodingKey {
                case studentId = "student_id"; case examName = "exam_name"
                case examDate = "exam_date"; case subject; case score
                case maxScore = "max_score"; case filePath = "file_path"
            }
        }
        let isoDate: String? = {
            guard let d = examDate else { return nil }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
        }()
        return try await db.from("result_slips")
            .insert(SlipInsert(studentId: studentId, examName: examName, examDate: isoDate,
                               subject: subject, score: score, maxScore: maxScore, filePath: path))
            .select().single().execute().value
    }

    func fetchResultSlips(studentId: UUID) async throws -> [ResultSlip] {
        return try await db.from("result_slips")
            .select()
            .eq("student_id", value: studentId)
            .order("uploaded_at", ascending: false)
            .execute().value
    }

    func resultSlipSignedURL(path: String) async throws -> URL {
        return try await db.storage.from("result-slips")
            .createSignedURL(path: path, expiresIn: 3600)
    }

    // MARK: - Parent linking (#13)

    func fetchParents() async throws -> [Profile] {
        return try await db.from("profiles")
            .select()
            .eq("role", value: "parent")
            .order("full_name")
            .execute().value
    }

    func fetchParentLinks(parentId: UUID) async throws -> [UUID] {
        struct Link: Codable { let studentId: UUID; enum CodingKeys: String, CodingKey { case studentId = "student_id" } }
        let rows: [Link] = try await db.from("parent_student_links")
            .select("student_id")
            .eq("parent_id", value: parentId)
            .execute().value
        return rows.map(\.studentId)
    }

    func linkParentToStudent(parentId: UUID, studentId: UUID) async throws {
        try await db.rpc("link_parent_student", params: [
            "p_parent": parentId.uuidString,
            "p_student": studentId.uuidString
        ]).execute()
    }

    func unlinkParentFromStudent(parentId: UUID, studentId: UUID) async throws {
        try await db.rpc("unlink_parent_student", params: [
            "p_parent": parentId.uuidString,
            "p_student": studentId.uuidString
        ]).execute()
    }

    // MARK: - Export helpers (#7)

    /// Fetches all attendance records for a class within a date range, for export.
    func fetchAttendanceForExport(classId: UUID, from: Date, to: Date) async throws -> [AttendanceRecord] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return try await db.from("attendance_records")
            .select("*, session:sessions!inner(session_date, class_id)")
            .eq("session.class_id", value: classId.uuidString)
            .gte("session.session_date", value: fmt.string(from: from))
            .lte("session.session_date", value: fmt.string(from: to))
            .order("session.session_date", ascending: true)
            .execute().value
    }
}

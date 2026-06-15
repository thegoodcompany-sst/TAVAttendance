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
        // Use upsert to avoid the TOCTOU race: concurrent kiosk loads on the same
        // (class_id, session_date) pair would violate the unique constraint with a
        // plain SELECT-then-INSERT. ON CONFLICT DO UPDATE is idempotent.
        let new = Session(id: UUID(), classId: classId, sessionDate: date, topic: nil, notes: nil, startedAt: nil, endedAt: nil, subTutorId: nil)
        return try await db.from("sessions")
            .upsert(new, onConflict: "class_id,session_date")
            .select().single().execute().value
    }

    /// Sets started_at = NOW(). Call only when the session has not yet been started.
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

    /// Sets ended_at = NOW(). Does not affect started_at or attendance records.
    func endSession(id: UUID) async throws {
        struct Patch: Encodable {
            let endedAt: Date
            enum CodingKeys: String, CodingKey { case endedAt = "ended_at" }
        }
        try await db.from("sessions")
            .update(Patch(endedAt: Date()))
            .eq("id", value: id)
            .execute()
    }

    /// Clears ended_at, reopening the session for attendance marking.
    func resumeSession(id: UUID) async throws {
        struct Patch: Encodable {
            enum CodingKeys: String, CodingKey { case endedAt = "ended_at" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeNil(forKey: .endedAt)
            }
        }
        try await db.from("sessions")
            .update(Patch())
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

        // Parallelize session creation — the upsert on (class_id, session_date) makes
        // concurrent calls safe; no TOCTOU race even if two tasks hit the DB at once.
        var sessionTuples: [(classId: UUID, session: Session)] = []
        try await withThrowingTaskGroup(of: (UUID, Session).self) { group in
            for cls in classes {
                group.addTask {
                    let session = try await self.getOrCreateSession(classId: cls.id, date: today)
                    return (cls.id, session)
                }
            }
            for try await tuple in group {
                sessionTuples.append(tuple)
            }
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
        // Upsert on (session_id, student_id) unique constraint to avoid duplicate rows
        // that would crash Dictionary(uniqueKeysWithValues:) in fetchTodaysDismissals.
        return try await db.from("dismissals")
            .upsert(DismissalInsert(sessionId: sessionId, studentId: studentId, dismissedAt: Date()),
                    onConflict: "session_id,student_id")
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

    // MARK: - PDPA: privacy notice (#N1)

    /// Fetches the current Data Protection Notice. Any authenticated user may read it.
    func fetchPrivacyNotice() async throws -> PolicyDocument? {
        let rows: [PolicyDocument] = try await db.from("policy_documents")
            .select()
            .eq("doc_type", value: "data_protection_notice")
            .eq("is_current", value: true)
            .order("published_at", ascending: false)
            .limit(1)
            .execute().value
        return rows.first
    }

    // MARK: - PDPA: consent ledger (#C1/#C2)

    private struct ConsentInsert: Encodable {
        let studentId: UUID
        let consentType: String
        let status: String
        let method: String
        let noticeVersion: String?
        let sourceNote: String?

        enum CodingKeys: String, CodingKey {
            case status, method
            case studentId     = "student_id"
            case consentType   = "consent_type"
            case noticeVersion = "notice_version"
            case sourceNote    = "source_note"
        }
    }

    /// Appends a consent row for a single student. `granted_by` is stamped server-side
    /// from auth.uid() defaults are not set, so we rely on RLS + the column being nullable;
    /// the DB records the acting admin via the row's RLS context where available.
    func recordConsent(
        studentId: UUID,
        consentType: String = "data_collection",
        status: ConsentStatus = .granted,
        method: String = "admin_attestation",
        noticeVersion: String?,
        sourceNote: String? = nil
    ) async throws {
        try await db.from("consent_records")
            .insert(ConsentInsert(
                studentId: studentId,
                consentType: consentType,
                status: status.rawValue,
                method: method,
                noticeVersion: noticeVersion,
                sourceNote: sourceNote))
            .execute()
    }

    /// Bulk-inserts consent rows (used by CSV import after students are created).
    func recordConsentBulk(
        studentIds: [UUID],
        consentType: String = "data_collection",
        method: String = "admin_attestation",
        noticeVersion: String?
    ) async throws {
        guard !studentIds.isEmpty else { return }
        let rows = studentIds.map {
            ConsentInsert(studentId: $0, consentType: consentType,
                          status: ConsentStatus.granted.rawValue, method: method,
                          noticeVersion: noticeVersion, sourceNote: "Bulk CSV import attestation")
        }
        try await db.from("consent_records").insert(rows).execute()
    }

    /// Returns the latest consent row per (student, type) for one student, from `current_consent`.
    func fetchCurrentConsent(studentId: UUID) async throws -> [ConsentRecord] {
        return try await db.from("current_consent")
            .select()
            .eq("student_id", value: studentId)
            .execute().value
    }

    /// Withdraws consent by appending a `withdrawn` row (append-only ledger).
    func withdrawConsent(studentId: UUID, consentType: String = "data_collection",
                         noticeVersion: String? = nil) async throws {
        try await recordConsent(studentId: studentId, consentType: consentType,
                                status: .withdrawn, method: "admin_attestation",
                                noticeVersion: noticeVersion,
                                sourceNote: "Withdrawn by admin")
    }

    // MARK: - PDPA: erase / anonymise (#R1/#R2)

    func anonymiseStudent(id: UUID) async throws {
        try await db.rpc("anonymise_student", params: ["p_student_id": id.uuidString]).execute()
    }

    func eraseStudent(id: UUID) async throws {
        try await db.rpc("erase_student", params: ["p_student_id": id.uuidString]).execute()
    }

    // MARK: - PDPA: subject-access export (#A2)

    /// Calls the admin-guarded RPC and returns the raw JSON bytes of the personal-data bundle.
    /// The RPC also logs a `data_disclosures` row server-side.
    func exportStudentPersonalData(id: UUID) async throws -> Data {
        // The RPC returns a JSONB value; capture it as raw Data so we can write it to disk verbatim.
        let response = try await db
            .rpc("export_student_personal_data", params: ["p_student_id": id.uuidString])
            .execute()
        return response.data
    }

    // MARK: - PDPA: correction requests (#A1)

    func fetchCorrectionRequests(status: CorrectionStatus = .pending) async throws -> [CorrectionRequest] {
        return try await db.from("correction_requests")
            .select()
            .eq("status", value: status.rawValue)
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Applies a correction: writes the new value onto the student row, then marks the
    /// request `applied` and logs a `correction_response` disclosure.
    func applyCorrection(_ request: CorrectionRequest) async throws {
        // Whitelist of correctable student columns to avoid arbitrary column writes.
        let allowed: Set<String> = ["full_name", "school", "year_of_study", "date_of_birth"]
        guard allowed.contains(request.fieldName) else {
            throw NSError(domain: "TAVA.Correction", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Field '\(request.fieldName)' cannot be auto-applied. Correct it manually, then mark this request applied."
            ])
        }
        let newValue = request.requestedValue
        try await db.from("students")
            .update([request.fieldName: newValue])
            .eq("id", value: request.studentId)
            .execute()

        try await markCorrection(id: request.id, status: .applied, note: nil)

        struct DisclosureInsert: Encodable {
            let studentId: UUID; let disclosureType: String; let detail: [String: String]?
            enum CodingKeys: String, CodingKey {
                case studentId = "student_id"; case disclosureType = "disclosure_type"; case detail
            }
        }
        try await db.from("data_disclosures")
            .insert(DisclosureInsert(
                studentId: request.studentId,
                disclosureType: "correction_response",
                detail: ["field": request.fieldName,
                         "new_value": request.requestedValue ?? ""]))
            .execute()
    }

    func rejectCorrection(id: UUID, note: String?) async throws {
        try await markCorrection(id: id, status: .rejected, note: note)
    }

    private func markCorrection(id: UUID, status: CorrectionStatus, note: String?) async throws {
        struct Patch: Encodable {
            let status: String
            let reviewedAt: Date
            let reviewNote: String?
            enum CodingKeys: String, CodingKey {
                case status
                case reviewedAt = "reviewed_at"
                case reviewNote = "review_note"
            }
        }
        try await db.from("correction_requests")
            .update(Patch(status: status.rawValue, reviewedAt: Date(), reviewNote: note))
            .eq("id", value: id)
            .execute()
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

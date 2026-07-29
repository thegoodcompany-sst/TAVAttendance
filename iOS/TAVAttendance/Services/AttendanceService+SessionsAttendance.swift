import Foundation
import Supabase

extension AttendanceService {
    // MARK: - Sessions

    func fetchSessions(for classId: UUID) async throws -> [Session] {
        return try await db.from("sessions").select()
            .eq("class_id", value: classId).order("session_date", ascending: false)
            .execute().value
    }

    func getOrCreateTodaySession(classId: UUID) async throws -> Session {
        // The database derives the Singapore civil date and handles the unique
        // create race. For substitutes it returns only their pre-assigned row;
        // it never turns a substitution into class-wide session-create authority.
        return try await db.rpc(
            "get_or_create_today_session",
            params: ["p_class_id": classId.uuidString]
        ).execute().value
    }

    /// Sets started_at = NOW(). Call only when the session has not yet been started.
    func startSession(id: UUID) async throws {
        try await db.rpc("set_session_lifecycle", params: [
            "p_session_id": id.uuidString,
            "p_action": "start",
        ]).execute()
    }

    /// Sets ended_at = NOW(). Does not affect started_at or attendance records.
    func endSession(id: UUID) async throws {
        try await db.rpc("set_session_lifecycle", params: [
            "p_session_id": id.uuidString,
            "p_action": "end",
        ]).execute()
    }

    /// Saves the tutor's free-text note on a session (flag `session_notes`).
    /// An empty note is stored as SQL NULL, sent explicitly (the SDK omits nil properties).
    func updateSessionNotes(id: UUID, notes: String?) async throws {
        struct Params: Encodable {
            let sessionId: UUID
            let notes: String?
            enum CodingKeys: String, CodingKey {
                case sessionId = "p_session_id"
                case notes = "p_notes"
            }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(sessionId, forKey: .sessionId)
                if let notes {
                    try container.encode(notes, forKey: .notes)
                } else {
                    try container.encodeNil(forKey: .notes)
                }
            }
        }
        try await db.rpc(
            "update_session_note",
            params: Params(sessionId: id, notes: notes)
        ).execute()
    }

    private struct CreateRetrospectiveSessionParams: Encodable {
        let classId: UUID
        let sessionDate: String
        let topic: String?
        let notes: String?
        let subTutorId: UUID?

        enum CodingKeys: String, CodingKey {
            case topic, notes
            case classId = "class_id"
            case sessionDate = "session_date"
            case subTutorId = "sub_tutor_id"
        }
    }

    private struct UpdateRetrospectiveSessionParams: Encodable {
        let sessionId: UUID
        let topic: String?
        let notes: String?
        let subTutorId: UUID?

        enum CodingKeys: String, CodingKey {
            case topic, notes
            case sessionId = "session_id"
            case subTutorId = "sub_tutor_id"
        }
    }

    func createRetrospectiveSession(
        classId: UUID, sessionDate: String, topic: String?, notes: String?, subTutorId: UUID?
    ) async throws -> Session {
        try await db.rpc(
            "create_retrospective_session",
            params: CreateRetrospectiveSessionParams(
                classId: classId, sessionDate: sessionDate, topic: topic,
                notes: notes, subTutorId: subTutorId)
        ).execute().value
    }

    func updateRetrospectiveSession(
        sessionId: UUID, topic: String?, notes: String?, subTutorId: UUID?
    ) async throws -> Session {
        try await db.rpc(
            "update_retrospective_session",
            params: UpdateRetrospectiveSessionParams(
                sessionId: sessionId, topic: topic, notes: notes,
                subTutorId: subTutorId)
        ).execute().value
    }

    // MARK: - Roster & Attendance

    func fetchRoster(sessionId: UUID) async throws -> [RosterEntry] {
        return try await db
            .rpc("get_session_roster", params: ["p_session_id": sessionId.uuidString])
            .execute().value
    }

    func fetchRetrospectiveRoster(sessionId: UUID) async throws -> [RosterEntry] {
        struct Params: Encodable {
            let sessionId: UUID
            enum CodingKeys: String, CodingKey { case sessionId = "session_id" }
        }
        return try await db
            .rpc("get_retrospective_session_roster", params: Params(sessionId: sessionId))
            .execute().value
    }

    func markRetrospectiveAttendance(
        sessionId: UUID, studentId: UUID, status: AttendanceStatus
    ) async throws {
        struct Params: Encodable {
            let sessionId: UUID
            let studentId: UUID
            let status: String
            enum CodingKeys: String, CodingKey {
                case status
                case sessionId = "session_id"
                case studentId = "student_id"
            }
        }
        try await db.rpc(
            "mark_retrospective_attendance",
            params: Params(sessionId: sessionId, studentId: studentId, status: status.rawValue)
        ).execute()
    }

    func markAttendance(sessionId: UUID, studentId: UUID, status: AttendanceStatus, notes: String? = nil, lateReason: String? = nil) async throws {
        let record = AttendanceInsert(
            sessionId: sessionId, studentId: studentId, status: status,
            notes: notes, lateReason: lateReason, clientMutationId: UUID().uuidString)
        try await db.from("attendance_records")
            .upsert(record, onConflict: "session_id,student_id").execute()
    }

    func fetchStudentAttendanceHistory(studentId: UUID, limit: Int = 100, since: Date? = nil) async throws -> [AttendanceHistoryRecord] {
        // QA-05: the `since` window must filter on the session date (the real class
        // date), not marked_at. An offline record marked weeks ago but synced today
        // belongs in the window for its session date. `!inner` makes session an INNER
        // join so the embedded `session_date` filter applies to the top-level rows.
        var filterBuilder = db
            .from("attendance_records")
            .select("id, status, marked_at, session:sessions!inner(session_date, class:classes!inner(name, is_study_space))")
            .eq("student_id", value: studentId)
            // Study Space attendance is internal-only — never show it in student history.
            .eq("session.class.is_study_space", value: false)

        if let since {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            filterBuilder = filterBuilder.gte("session.session_date", value: fmt.string(from: since))
        }

        return try await filterBuilder
            .order("marked_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Parent-safe attendance projection. The RPC returns the same nested
    /// `session` JSON shape as the staff PostgREST query without notes, actor
    /// identifiers, or offline mutation IDs.
    func syncPending(_ records: [PendingAttendanceRecord]) async throws -> (synced: Int, skipped: Int, blockedEndedSession: Int) {
        guard let currentUserId = db.auth.currentSession?.user.id else {
            throw AppError("Cannot sync attendance without an authenticated account.")
        }
        guard PendingAttendanceQueueCodec.recordsBelongToOwner(
            records,
            ownerUserId: currentUserId
        ) else {
            throw AppError("Pending attendance belongs to a different account.")
        }
        let payload = records.map { r -> [String: String] in
            ["session_id": r.sessionId.uuidString, "student_id": r.studentId.uuidString,
             "status": r.status.rawValue, "notes": r.notes ?? "",
             "client_mutation_id": r.clientMutationId,
             "marked_at": ISO8601DateFormatter().string(from: r.markedAt)]
        }
        // Decode all three counters (migration 013 + 016). skipped (newer server row
        // won) and blocked_ended_session (session already ended) are both TERMINAL —
        // the record will never sync — so the caller clears them from the store on any
        // successful RPC, not just when synced > 0.
        let result: [String: Int] = try await db
            .rpc("sync_attendance", params: ["records": payload]).execute().value
        return (result["synced"] ?? 0, result["skipped"] ?? 0, result["blocked_ended_session"] ?? 0)
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

}

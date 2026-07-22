import Foundation
import Supabase

final class AttendanceService {
    static let shared = AttendanceService()
    private let db = SupabaseManager.shared.client

    /// "yyyy-MM-dd" formatter pinned to a POSIX Gregorian calendar. A device set to a
    /// non-Gregorian calendar (e.g. Buddhist/Japanese) would otherwise format session
    /// dates in that calendar's era/year, splitting kiosk vs tutor sessions for the
    /// same real day. Used for session_date reads/writes.
    static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    // MARK: - Classes

    func fetchMyClasses() async throws -> [TAVClass] {
        // The shaped RPC includes current assignments plus recent sessions the
        // caller is explicitly covering as a substitute.
        return try await db.rpc("get_my_classes").execute().value
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

    /// Parent-safe projection. Migration 038 removes direct parent SELECT on
    /// `students` so staff-only notes, birth dates, and actor IDs never cross
    /// the Data API boundary.
    func fetchParentChildren() async throws -> [Student] {
        return try await db.rpc("get_parent_children").execute().value
    }

    private struct CreateStudentWithConsentParams: Encodable {
        let fullName: String
        let school: String?
        let yearOfStudy: String?
        let sourceNote: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "p_full_name"
            case school = "p_school"
            case yearOfStudy = "p_year_of_study"
            case sourceNote = "p_source_note"
        }
    }

    /// Creates the student and mandatory consent ledger row in one DB transaction.
    func createStudentWithConsent(_ student: StudentInsert, sourceNote: String? = nil) async throws -> Student {
        return try await db.rpc(
            "create_student_with_consent",
            params: CreateStudentWithConsentParams(
                fullName: student.fullName,
                school: student.school,
                yearOfStudy: student.yearOfStudy,
                sourceNote: sourceNote
            )
        ).execute().value
    }

    func updateStudent(id: UUID, _ student: StudentInsert) async throws {
        try await db.from("students").update(student).eq("id", value: id).execute()
    }

    func deactivateStudent(id: UUID) async throws {
        try await db.from("students").update(["is_active": false]).eq("id", value: id).execute()
    }

    // MARK: - Student results (migration 023)

    /// RLS scopes rows to the caller: admins see all, tutors only students
    /// enrolled in their assigned classes.
    func fetchStudentResults() async throws -> [StudentResult] {
        return try await db.from("student_results").select().execute().value
    }

    func upsertStudentResult(studentId: UUID, subject: ResultSlipSubject, grade: String) async throws {
        let record = StudentResultUpsert(
            studentId: studentId,
            subject: subject.rawValue,
            grade: grade,
            updatedBy: db.auth.currentSession?.user.id)
        try await db.from("student_results")
            .upsert(record, onConflict: "student_id,subject")
            .execute()
    }

    func deleteStudentResult(studentId: UUID, subject: ResultSlipSubject) async throws {
        try await db.from("student_results").delete()
            .eq("student_id", value: studentId)
            .eq("subject", value: subject.rawValue)
            .execute()
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
        // MAINT-04: record when the unenrolment happened, not just is_active=false.
        struct Unenroll: Encodable {
            let isActive: Bool
            let unenrolledAt: String
            enum CodingKeys: String, CodingKey {
                case isActive = "is_active"
                case unenrolledAt = "unenrolled_at"
            }
        }
        let now = ISO8601DateFormatter().string(from: Date())
        try await db.from("enrollments")
            .update(Unenroll(isActive: false, unenrolledAt: now))
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

    func assignTutor(tutorId: UUID, classId: UUID, assignedUntil: Date? = nil) async throws {
        // MAINT-05: assigned_until can now be set (an end date for the assignment);
        // tutor_owns_class() honours it (NULL = open-ended). nil omits the column.
        struct AssignInsert: Encodable {
            let classId: UUID; let tutorId: UUID; let assignedUntil: String?
            enum CodingKeys: String, CodingKey {
                case classId = "class_id"; case tutorId = "tutor_id"; case assignedUntil = "assigned_until"
            }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let untilStr = assignedUntil.map { fmt.string(from: $0) }
        try await db.from("class_tutor_assignments")
            .upsert(AssignInsert(classId: classId, tutorId: tutorId, assignedUntil: untilStr), onConflict: "class_id,tutor_id")
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

    // MARK: - Global kiosk

    func fetchKioskEntries() async throws -> [KioskEntry] {
        // Day-aware: only create/show sessions for classes scheduled today, so opening
        // the kiosk on a non-tuition day doesn't spin up phantom sessions. Supports
        // multiple classes on the same day (e.g. Thu English + Thu Reading).
        let todayWeekday = Self.weekdayName(for: Date())
        // test_mode (migration 020) bypasses the day filter so demos/testing on
        // non-tuition days still show every active class.
        let testMode = await FeatureFlagStore.shared.isEnabled(.testMode)
        let classes = try await fetchMyClasses().filter {
            $0.canOperateTodaySession == true
                && (testMode || Self.classMeetsToday($0, weekday: todayWeekday))
        }
        let classMap = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })

        // Parallelize session creation — the upsert on (class_id, session_date) makes
        // concurrent calls safe; no TOCTOU race even if two tasks hit the DB at once.
        var sessionTuples: [(classId: UUID, session: Session)] = []
        try await withThrowingTaskGroup(of: (UUID, Session).self) { group in
            for cls in classes {
                group.addTask {
                    let session = try await self.getOrCreateTodaySession(classId: cls.id)
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
                            status: r.status, sessions: [slot], markedAt: r.markedAt,
                            avatarUrl: r.avatarUrl)
                    }
                }
            }
        }
        return Array(entryMap.values).sorted { $0.fullName < $1.fullName }
    }

    // late > present > absent > excused — worst shown when a student spans multiple sessions
    static func worstStatus(_ a: AttendanceStatus?, _ b: AttendanceStatus?) -> AttendanceStatus? {
        let rank: [AttendanceStatus: Int] = [.late: 4, .present: 3, .absent: 2, .excused: 1]
        switch (a, b) {
        case (nil, let x): return x
        case (let x, nil): return x
        case (let x?, let y?): return (rank[y] ?? 0) > (rank[x] ?? 0) ? y : x
        }
    }

    /// Parses a kiosk QR payload into a student UUID. Tolerates surrounding whitespace
    /// (some QR generators append a trailing newline); anything else is rejected.
    static func studentId(fromQRPayload payload: String) -> UUID? {
        UUID(uuidString: payload.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Marks a student across all their today's sessions. Status is applied as-is to every session.
    func markKioskAttendance(entry: KioskEntry, status: AttendanceStatus, lateReason: String? = nil) async throws {
        for session in entry.sessions {
            try await markAttendance(sessionId: session.id, studentId: entry.studentId, status: status, lateReason: lateReason)
        }
    }

    /// Marks each session independently: late if the class has already started, present otherwise.
    /// Returns the worst status marked (late if any session was late), for immediate UI display.
    @discardableResult
    func markKioskSignIn(entry: KioskEntry) async throws -> AttendanceStatus {
        let now = Date()
        var worst: AttendanceStatus = .present

        for session in entry.sessions {
            let status = Self.signInStatus(scheduleTime: session.scheduleTime, startedAt: session.startedAt, now: now)
            try await markAttendance(sessionId: session.id, studentId: entry.studentId, status: status)
            if status == .late { worst = .late }
        }
        return worst
    }

    /// Auto-late decision for a single kiosk sign-in. A teacher-started class (`startedAt`
    /// in the past) forces `.late`; otherwise the class's `scheduleTime` — a Postgres TIME
    /// rendered as "HH:mm:ss" by PostgREST or "HH:mm" from free-text entry — is parsed by
    /// splitting on ":" and taking the first two components (never assume exactly two).
    /// Malformed or short strings fall through to `.present`.
    static func signInStatus(scheduleTime: String?, startedAt: Date?, now: Date, calendar: Calendar = .current) -> AttendanceStatus {
        if let startedAt, now > startedAt {
            return .late
        }
        if let timeStr = scheduleTime {
            let parts = timeStr.split(separator: ":").compactMap { Int($0) }
            if parts.count >= 2 {
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = parts[0]
                components.minute = parts[1]
                components.second = 0
                if let classStart = calendar.date(from: components), now > classStart {
                    return .late
                }
            }
        }
        return .present
    }

    // MARK: - Day-of-week scheduling

    /// English full weekday name ("Monday"…"Sunday") for the given date.
    static func weekdayName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    /// Whether a class meets on `weekday` (an English full weekday name). A class's
    /// `recurrence_rule` BYDAY wins when present; otherwise `schedule_day` is matched;
    /// a class with neither set is treated as ad-hoc and always shown.
    static func classMeetsToday(_ cls: TAVClass, weekday: String) -> Bool {
        if let rule = cls.recurrenceRule, let codes = bydayCodes(from: rule), !codes.isEmpty {
            return codes.contains(weekdayCode(weekday))
        }
        if let day = cls.scheduleDay, !day.isEmpty {
            return day.caseInsensitiveCompare(weekday) == .orderedSame
        }
        return true
    }

    /// Two-letter RRULE day code for an English weekday name ("Monday" → "MO").
    private static func weekdayCode(_ weekday: String) -> String {
        switch weekday.lowercased() {
        case "monday":    return "MO"
        case "tuesday":   return "TU"
        case "wednesday": return "WE"
        case "thursday":  return "TH"
        case "friday":    return "FR"
        case "saturday":  return "SA"
        case "sunday":    return "SU"
        default:          return ""
        }
    }

    /// Extracts the BYDAY codes from an RRULE string, e.g. "FREQ=WEEKLY;BYDAY=MO,TH" → ["MO","TH"].
    private static func bydayCodes(from rule: String) -> [String]? {
        for part in rule.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0].uppercased() == "BYDAY" {
                return kv[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            }
        }
        return nil
    }

    // MARK: - Study Space (internal-only; migration 015)

    /// The singleton internal Study Space (drop-in room) class. Attendance here is
    /// Present / Not Here only and is EXCLUDED from all reports & parent views.
    static let studySpaceClassId = UUID(uuidString: "57000000-0000-0000-0000-000000000001")!

    /// Loads today's Study Space session (creating it on first use) and the roster of
    /// ALL active students with their current Present/Not-Here status for it.
    func loadStudySpace() async throws -> (session: Session, roster: [RosterEntry]) {
        let session = try await getOrCreateTodaySession(classId: Self.studySpaceClassId)
        let roster: [RosterEntry] = try await db
            .rpc("get_study_space_roster", params: ["p_session_id": session.id.uuidString])
            .execute().value
        return (session, roster)
    }

    /// Fetches a student's recent attendance history with class name, for the profile sheet.
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
    func fetchParentAttendanceHistory(
        studentId: UUID,
        limit: Int = 100,
        since: Date? = nil
    ) async throws -> [AttendanceHistoryRecord] {
        struct Params: Encodable {
            let studentId: UUID
            let limit: Int
            let since: String?

            enum CodingKeys: String, CodingKey {
                case studentId = "p_student_id"
                case limit = "p_limit"
                case since = "p_since"
            }
        }

        return try await db.rpc(
            "get_parent_attendance_history",
            params: Params(
                studentId: studentId,
                limit: limit,
                since: since.map(Self.ymdFormatter.string(from:))
            )
        ).execute().value
    }

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

    // MARK: - Safely home (migration 030, flag: push_notifications)

    /// Parent-safe dismissal projection; session and actor identifiers stay server-side.
    func fetchTodayDismissals() async throws -> [Dismissal] {
        return try await db.rpc("get_parent_dismissals").execute().value
    }

    /// Dismissals still awaiting a parent's safely-home confirmation.
    static func awaitingSafelyHome(_ dismissals: [Dismissal]) -> [Dismissal] {
        dismissals.filter { $0.safelyHomeAt == nil && $0.dismissedAt != nil }
    }

    /// Parent-only, once-only: sets safely_home_at on the child's dismissal row.
    /// Server enforces ownership and immutability (mark_safely_home, migration 030).
    func markSafelyHome(dismissalId: UUID) async throws {
        try await db.rpc("mark_safely_home", params: ["p_dismissal_id": dismissalId.uuidString]).execute()
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

    func bulkCreateStudentsWithConsent(_ rows: [StudentInsert]) async throws -> [Student] {
        var created: [Student] = []
        created.reserveCapacity(rows.count)
        for row in rows {
            created.append(try await createStudentWithConsent(row, sourceNote: "Bulk CSV import"))
        }
        return created
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

    // MARK: - Result slips (#20 / parent portal Phase 2)

    /// Parent-safe projection installed by migration 038.
    func fetchResultSlips(studentId: UUID) async throws -> [ResultSlip] {
        return try await db.rpc(
            "get_parent_result_slips",
            params: ["p_student_id": studentId.uuidString]
        ).execute().value
    }

    /// Staff retain their RLS-scoped base-table view.
    func fetchStaffResultSlips(studentId: UUID) async throws -> [ResultSlip] {
        return try await db.from("result_slips")
            .select()
            .eq("student_id", value: studentId)
            .order("uploaded_at", ascending: false)
            .execute().value
    }

    /// Parent-only text result submission; the server derives uploaded_by from auth.uid().
    func submitResultSlip(
        studentId: UUID,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double
    ) async throws -> ResultSlip {
        struct Params: Encodable {
            let studentId: UUID
            let examName: String
            let examDate: String
            let subject: String
            let score: Double
            let maxScore: Double

            enum CodingKeys: String, CodingKey {
                case studentId = "p_student_id"
                case examName  = "p_exam_name"
                case examDate  = "p_exam_date"
                case subject   = "p_subject"
                case score     = "p_score"
                case maxScore  = "p_max_score"
            }
        }
        let rows: [ResultSlip] = try await db.rpc(
            "submit_parent_result_slip",
            params: Params(
                studentId: studentId,
                examName: examName,
                examDate: examDate,
                subject: subject,
                score: score,
                maxScore: maxScore
            )
        ).execute().value
        guard let result = rows.first else {
            throw AppError("Result submission returned no result.")
        }
        return result
    }

    // MARK: - Parent messages (Phase 2)

    func fetchMessages(studentId: UUID) async throws -> [ParentMessage] {
        return try await db.rpc(
            "get_parent_messages",
            params: ["p_student_id": studentId.uuidString]
        ).execute().value
    }

    func sendParentMessage(
        studentId: UUID,
        subject: String?,
        body: String
    ) async throws -> ParentMessage {
        struct Params: Encodable {
            let studentId: UUID
            let subject: String?
            let body: String

            enum CodingKeys: String, CodingKey {
                case studentId = "p_student_id"
                case subject   = "p_subject"
                case body      = "p_body"
            }
        }
        let rows: [ParentMessage] = try await db.rpc(
            "send_parent_message",
            params: Params(
                studentId: studentId,
                subject: subject,
                body: body
            )
        ).execute().value
        guard let message = rows.first else {
            throw AppError("Message submission returned no result.")
        }
        return message
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

    private struct RecordAdminConsentParams: Encodable {
        let studentId: UUID
        let consentType: String
        let status: String
        let sourceNote: String?

        enum CodingKeys: String, CodingKey {
            case studentId   = "p_student_id"
            case consentType = "p_consent_type"
            case status      = "p_status"
            case sourceNote  = "p_source_note"
        }
    }

    /// Appends a consent row through the shaped database RPC. The database
    /// derives the actor, method, current notice version and timestamp.
    func recordConsent(
        studentId: UUID,
        consentType: String = "data_collection",
        status: ConsentStatus = .granted,
        sourceNote: String? = nil
    ) async throws {
        try await db.rpc(
            "record_admin_consent",
            params: RecordAdminConsentParams(
                studentId: studentId,
                consentType: consentType,
                status: status.rawValue,
                sourceNote: sourceNote
            )
        ).execute()
    }

    /// Records bulk consent via the same shaped RPC for each student. Student
    /// creation itself should normally use create_student_with_consent instead.
    func recordConsentBulk(
        studentIds: [UUID],
        consentType: String = "data_collection"
    ) async throws {
        for studentId in studentIds {
            try await recordConsent(
                studentId: studentId,
                consentType: consentType,
                status: .granted,
                sourceNote: "Bulk CSV import attestation"
            )
        }
    }

    /// Returns the latest consent row per (student, type) for one student, from `current_consent`.
    func fetchCurrentConsent(studentId: UUID) async throws -> [ConsentRecord] {
        return try await db.from("current_consent")
            .select()
            .eq("student_id", value: studentId)
            .execute().value
    }

    /// Withdraws consent by appending a `withdrawn` row (append-only ledger).
    func withdrawConsent(studentId: UUID,
                         consentType: String = "data_collection") async throws {
        try await recordConsent(studentId: studentId, consentType: consentType,
                                status: .withdrawn,
                                sourceNote: "Withdrawn by admin")
    }

    // MARK: - PDPA: erase / pseudonymise (#R1/#R2)

    func anonymiseStudent(id: UUID) async throws {
        throw AppError(
            "Pseudonymisation is available only in the secure admin web dashboard."
        )
    }

    func eraseStudent(id: UUID) async throws {
        throw AppError(
            "Erasure is available only in the secure admin web dashboard."
        )
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

    /// The database reviews, applies and logs the correction atomically.
    func applyCorrection(_ request: CorrectionRequest) async throws {
        try await reviewCorrection(id: request.id, decision: .applied, note: nil)
    }

    func rejectCorrection(id: UUID, note: String?) async throws {
        try await reviewCorrection(id: id, decision: .rejected, note: note)
    }

    private func reviewCorrection(
        id: UUID,
        decision: CorrectionStatus,
        note: String?
    ) async throws {
        struct Params: Encodable {
            let requestId: UUID
            let decision: String
            let reviewNote: String?
            enum CodingKeys: String, CodingKey {
                case requestId = "p_request_id"
                case decision = "p_decision"
                case reviewNote = "p_review_note"
            }
        }
        try await db
            .rpc(
                "review_correction_request",
                params: Params(
                    requestId: id,
                    decision: decision.rawValue,
                    reviewNote: note
                )
            )
            .execute()
    }

    // MARK: - Student photos (PROD-04, flag: student_photos)

    /// Uploads a student photo to the `student-photos` bucket and stores its path
    /// on the student row. Returns the storage path.
    func uploadStudentPhoto(studentId: UUID, fileData: Data, fileName: String, mime: String) async throws -> String {
        let maxBytes = 5 * 1024 * 1024
        guard fileData.count <= maxBytes else {
            throw AppError("This photo is too large. Please choose an image under 5 MB.")
        }
        let path = "\(studentId.uuidString.lowercased())/\(UUID().uuidString)-\(fileName)"
        try await db.storage.from("student-photos")
            .upload(path: path, file: fileData, options: .init(contentType: mime, upsert: true))
        try await db.from("students")
            .update(["avatar_url": path])
            .eq("id", value: studentId)
            .execute()
        return path
    }

    /// A short-lived signed URL for a private student photo path.
    func signedStudentPhotoURL(path: String) async throws -> URL {
        try await db.storage.from("student-photos").createSignedURL(path: path, expiresIn: 3600)
    }

    // MARK: - Device tokens (PROD-02, flag: push_notifications)

    /// Registers this device's push token for the signed-in user so the
    /// notify-parent edge function can reach them. Idempotent on the token.
    func registerDeviceToken(_ token: String, platform: String = "ios") async throws {
        struct Params: Encodable {
            let token: String; let platform: String
            enum CodingKeys: String, CodingKey {
                case token = "p_token"; case platform = "p_platform"
            }
        }
        try await db.rpc(
            "register_device_token",
            params: Params(token: token, platform: platform)
        ).execute()
    }

    // MARK: - Export helpers (#7)

    /// Fetches all attendance records for a class within a date range, for export.
    ///
    /// DOC-05: the `session:sessions!inner(...)` modifier is an INNER join — the
    /// `!inner` is required so that records whose session falls outside the date
    /// filter are excluded. Dropping `!inner` would turn this into a LEFT join and
    /// pull in every attendance row regardless of `session.session_date`. See
    /// PostgREST resource embedding docs ("!inner").
    ///
    /// QA-04 / MAINT-06: returns the joined `session_date` so the export uses the
    /// true session date (not `marked_at`, which is wrong for offline-synced rows).
    func fetchAttendanceForExport(classId: UUID, from: Date, to: Date) async throws -> [AttendanceExportRecord] {
        let fmt = Self.ymdFormatter
        return try await db.from("attendance_records")
            .select("student_id, status, marked_at, late_reason, session:sessions!inner(session_date, class_id)")
            .eq("session.class_id", value: classId.uuidString)
            .gte("session.session_date", value: fmt.string(from: from))
            .lte("session.session_date", value: fmt.string(from: to))
            .order("session.session_date", ascending: true)
            .execute().value
    }
}

/// Attendance row joined with its session date, used by the export screen.
/// QA-04: carries the authoritative `session_date` so the CSV/PDF "Date" column
/// is correct even for records that were marked offline and synced on a later day.
struct AttendanceExportRecord: Codable {
    let studentId: UUID
    let status: AttendanceStatus
    let markedAt: Date?
    let lateReason: String?
    let session: SessionDate

    /// The session date is the true class date; `sessionDate` is "yyyy-MM-dd".
    var sessionDate: String { session.sessionDate }

    struct SessionDate: Codable {
        let sessionDate: String
        enum CodingKeys: String, CodingKey { case sessionDate = "session_date" }
    }

    enum CodingKeys: String, CodingKey {
        case studentId  = "student_id"
        case status
        case markedAt   = "marked_at"
        case lateReason = "late_reason"
        case session
    }
}

import Foundation
import Supabase

extension AttendanceService {
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
                        if existing.absenceInformed == nil {
                            existing.absenceInformed = r.absenceInformed
                        }
                        entryMap[r.studentId] = existing
                    } else {
                        entryMap[r.studentId] = KioskEntry(
                            studentId: r.studentId, fullName: r.fullName,
                            status: r.status, sessions: [slot], markedAt: r.markedAt,
                            absenceInformed: r.absenceInformed,
                            avatarUrl: r.avatarUrl)
                    }
                }
            }
        }
        return Array(entryMap.values).sorted { $0.fullName < $1.fullName }
    }

    // late > present > absent — worst shown when a student spans multiple sessions
    static func worstStatus(_ a: AttendanceStatus?, _ b: AttendanceStatus?) -> AttendanceStatus? {
        let rank: [AttendanceStatus: Int] = [.late: 3, .present: 2, .absent: 1]
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
    func markKioskAttendance(
        entry: KioskEntry, status: AttendanceStatus,
        lateReason: String? = nil, absenceInformed: Bool? = nil
    ) async throws {
        for session in entry.sessions {
            try await markAttendance(
                sessionId: session.id, studentId: entry.studentId,
                status: status, lateReason: lateReason,
                absenceInformed: absenceInformed)
        }
    }

    func clearKioskAttendance(entry: KioskEntry) async throws {
        for session in entry.sessions {
            try await clearAttendance(sessionId: session.id, studentId: entry.studentId)
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
    /// Present / Not Here Yet only and is EXCLUDED from all reports & parent views.
    static let studySpaceClassId = UUID(uuidString: "57000000-0000-0000-0000-000000000001")!

    /// Loads today's Study Space session (creating it on first use) and the roster of
    /// ALL active students with their current Present/Not-Here-Yet status for it.
    func loadStudySpace() async throws -> (session: Session, roster: [RosterEntry]) {
        let session = try await getOrCreateTodaySession(classId: Self.studySpaceClassId)
        let roster: [RosterEntry] = try await db
            .rpc("get_study_space_roster", params: ["p_session_id": session.id.uuidString])
            .execute().value
        return (session, roster)
    }

    /// Fetches a student's recent attendance history with class name, for the profile sheet.
    // MARK: - Dismissals (#15)

    func recordDismissal(sessionId: UUID, studentId: UUID) async throws -> Dismissal {
        struct DismissalInsert: Encodable {
            let sessionId: UUID; let studentId: UUID; let dismissedAt: Date
            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"; case studentId = "student_id"; case dismissedAt = "dismissed_at"
            }
        }
        // A student can have one dismissal per session; the upsert keeps retries idempotent.
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
        return Self.latestDismissalsByStudent(rows)
    }

    static func latestDismissalsByStudent(_ rows: [Dismissal]) -> [UUID: Dismissal] {
        Dictionary(rows.map { ($0.studentId, $0) }, uniquingKeysWith: {
            ($0.dismissedAt ?? .distantPast) >= ($1.dismissedAt ?? .distantPast) ? $0 : $1
        })
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

}

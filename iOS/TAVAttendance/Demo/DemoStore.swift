import Foundation

/// In-memory backend for demo mode. Mirrors the behaviour of the Supabase RPCs
/// and tables that `AttendanceService` uses, closely enough for a live demo:
/// three-valued attendance, "Not Here Yet" as the absence of a row, Study Space
/// excluded from history/reports, and server-assigned timestamps.
///
/// Thread-safe via a lock; every method is synchronous and never does I/O.
final class DemoStore: @unchecked Sendable {
    static let shared = DemoStore()

    private let lock = NSLock()
    private var data: DemoDataset
    private let nowProvider: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        nowProvider = now
        data = DemoSeed.make(now: now())
    }

    /// Throws away every demo change and reseeds from scratch.
    func reset() {
        lock.lock()
        data = DemoSeed.make(now: nowProvider())
        lock.unlock()
    }

    private func read<T>(_ body: (DemoDataset) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(data)
    }

    private func write<T>(_ body: (inout DemoDataset) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&data)
    }

    private var now: Date { nowProvider() }
    private var todayString: String { AttendanceService.ymdFormatter.string(from: now) }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Snapshot for tests.
    var snapshot: DemoDataset { read { $0 } }

    // MARK: - Classes

    func fetchMyClasses() -> [TAVClass] {
        read { d in
            d.classes.filter { $0.isActive && $0.isStudySpace != true }
                .sorted { $0.name < $1.name }
        }
    }

    func createClass(_ cls: ClassInsert) -> TAVClass {
        let created = TAVClass(
            id: UUID(), name: cls.name, subject: cls.subject, level: cls.level,
            scheduleDay: cls.scheduleDay, scheduleTime: cls.scheduleTime,
            durationMinutes: cls.durationMinutes, isActive: cls.isActive,
            recurrenceRule: cls.recurrenceRule, recurrenceEndDate: cls.recurrenceEndDate,
            isStudySpace: false, canManageSessions: true, canOperateTodaySession: true)
        write { $0.classes.append(created) }
        return created
    }

    func updateClass(id: UUID, _ cls: ClassInsert) throws {
        try write { d in
            guard let i = d.classes.firstIndex(where: { $0.id == id }) else { throw DemoModeError.notFound("class") }
            let old = d.classes[i]
            d.classes[i] = TAVClass(
                id: id, name: cls.name, subject: cls.subject, level: cls.level,
                scheduleDay: cls.scheduleDay, scheduleTime: cls.scheduleTime,
                durationMinutes: cls.durationMinutes, isActive: cls.isActive,
                recurrenceRule: cls.recurrenceRule, recurrenceEndDate: cls.recurrenceEndDate,
                isStudySpace: old.isStudySpace, canManageSessions: old.canManageSessions,
                canOperateTodaySession: old.canOperateTodaySession)
        }
    }

    func deleteClass(id: UUID) throws {
        try write { d in
            guard let i = d.classes.firstIndex(where: { $0.id == id }) else { throw DemoModeError.notFound("class") }
            let c = d.classes[i]
            d.classes[i] = TAVClass(
                id: c.id, name: c.name, subject: c.subject, level: c.level,
                scheduleDay: c.scheduleDay, scheduleTime: c.scheduleTime,
                durationMinutes: c.durationMinutes, isActive: false,
                recurrenceRule: c.recurrenceRule, recurrenceEndDate: c.recurrenceEndDate,
                isStudySpace: c.isStudySpace, canManageSessions: c.canManageSessions,
                canOperateTodaySession: c.canOperateTodaySession)
        }
    }

    // MARK: - Students

    func fetchAllStudents() -> [Student] {
        read { d in d.students.filter(\.isActive).sorted { $0.fullName < $1.fullName } }
    }

    func fetchParentChildren() -> [Student] { [] }

    func createStudent(_ student: StudentInsert) -> Student {
        let created = Student(
            id: UUID(), fullName: student.fullName, school: student.school,
            yearOfStudy: student.yearOfStudy, isActive: true, avatarUrl: nil)
        write { d in
            d.students.append(created)
            d.consents.append(ConsentRecord(
                studentId: created.id, consentType: "data_collection", status: .granted,
                method: "admin_attested", noticeVersion: d.privacyNotice.version,
                grantedBy: DemoMode.userId, parentId: nil, createdAt: now))
        }
        return created
    }

    func updateStudent(id: UUID, _ student: StudentInsert) throws {
        try write { d in
            guard let i = d.students.firstIndex(where: { $0.id == id }) else { throw DemoModeError.notFound("student") }
            let old = d.students[i]
            d.students[i] = Student(
                id: id, fullName: student.fullName, school: student.school,
                yearOfStudy: student.yearOfStudy, isActive: old.isActive, avatarUrl: old.avatarUrl)
        }
    }

    func deactivateStudent(id: UUID) throws {
        try write { d in
            guard let i = d.students.firstIndex(where: { $0.id == id }) else { throw DemoModeError.notFound("student") }
            let old = d.students[i]
            d.students[i] = Student(
                id: id, fullName: old.fullName, school: old.school,
                yearOfStudy: old.yearOfStudy, isActive: false, avatarUrl: old.avatarUrl)
        }
    }

    // MARK: - Results

    func fetchStudentResults() -> [StudentResult] { read { $0.results } }

    func upsertStudentResult(studentId: UUID, subject: ResultSlipSubject, grade: String) {
        write { d in
            let row = StudentResult(
                id: d.results.first { $0.studentId == studentId && $0.subject == subject.rawValue }?.id ?? UUID(),
                studentId: studentId, subject: subject.rawValue, grade: grade)
            d.results.removeAll { $0.studentId == studentId && $0.subject == subject.rawValue }
            d.results.append(row)
        }
    }

    func deleteStudentResult(studentId: UUID, subject: ResultSlipSubject) {
        write { d in d.results.removeAll { $0.studentId == studentId && $0.subject == subject.rawValue } }
    }

    // MARK: - Enrollments & tutors

    func fetchEnrollments(classId: UUID) -> [Enrollment] {
        read { d in d.enrollments.filter { $0.classId == classId && $0.isActive } }
    }

    func enrollStudent(studentId: UUID, classId: UUID) {
        write { d in
            if let i = d.enrollments.firstIndex(where: { $0.studentId == studentId && $0.classId == classId }) {
                let e = d.enrollments[i]
                d.enrollments[i] = Enrollment(id: e.id, studentId: studentId, classId: classId, isActive: true)
            } else {
                d.enrollments.append(Enrollment(id: UUID(), studentId: studentId, classId: classId, isActive: true))
            }
        }
    }

    func unenrollStudent(studentId: UUID, classId: UUID) {
        write { d in
            for i in d.enrollments.indices where d.enrollments[i].studentId == studentId && d.enrollments[i].classId == classId {
                let e = d.enrollments[i]
                d.enrollments[i] = Enrollment(id: e.id, studentId: studentId, classId: classId, isActive: false)
            }
        }
    }

    func fetchTutors() -> [Profile] {
        read { d in d.profiles.filter { $0.role == "tutor" }.sorted { $0.fullName < $1.fullName } }
    }

    func fetchTutorAssignments(classId: UUID) -> [TutorAssignment] {
        read { d in d.assignments.filter { $0.classId == classId } }
    }

    func assignTutor(tutorId: UUID, classId: UUID) {
        write { d in
            guard !d.assignments.contains(where: { $0.tutorId == tutorId && $0.classId == classId }) else { return }
            d.assignments.append(TutorAssignment(id: UUID(), classId: classId, tutorId: tutorId))
        }
    }

    func unassignTutor(tutorId: UUID, classId: UUID) {
        write { d in d.assignments.removeAll { $0.tutorId == tutorId && $0.classId == classId } }
    }

    // MARK: - Sessions

    func fetchSessions(for classId: UUID) -> [Session] {
        read { d in d.sessions.filter { $0.classId == classId }.sorted { $0.sessionDate > $1.sessionDate } }
    }

    func getOrCreateTodaySession(classId: UUID) -> Session {
        let today = todayString
        return write { d in
            if let existing = d.sessions.first(where: { $0.classId == classId && $0.sessionDate == today }) {
                return existing
            }
            let created = Session(
                id: UUID(), classId: classId, sessionDate: today, topic: nil, notes: nil,
                startedAt: nil, endedAt: nil, subTutorId: nil)
            d.sessions.append(created)
            return created
        }
    }

    private func updateSession(_ id: UUID, _ change: (Session) -> Session) throws {
        try write { d in
            guard let i = d.sessions.firstIndex(where: { $0.id == id }) else { throw DemoModeError.notFound("session") }
            d.sessions[i] = change(d.sessions[i])
        }
    }

    func startSession(id: UUID) throws {
        let at = now
        try updateSession(id) { s in
            Session(id: s.id, classId: s.classId, sessionDate: s.sessionDate, topic: s.topic,
                    notes: s.notes, startedAt: s.startedAt ?? at, endedAt: s.endedAt, subTutorId: s.subTutorId)
        }
    }

    func endSession(id: UUID) throws {
        let at = now
        try updateSession(id) { s in
            Session(id: s.id, classId: s.classId, sessionDate: s.sessionDate, topic: s.topic,
                    notes: s.notes, startedAt: s.startedAt, endedAt: at, subTutorId: s.subTutorId)
        }
    }

    func updateSessionNotes(id: UUID, notes: String?) throws {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : notes
        try updateSession(id) { s in
            Session(id: s.id, classId: s.classId, sessionDate: s.sessionDate, topic: s.topic,
                    notes: value, startedAt: s.startedAt, endedAt: s.endedAt, subTutorId: s.subTutorId)
        }
    }

    func setSessionSubstitute(sessionId: UUID, tutorId: UUID?) throws {
        try updateSession(sessionId) { s in
            Session(id: s.id, classId: s.classId, sessionDate: s.sessionDate, topic: s.topic,
                    notes: s.notes, startedAt: s.startedAt, endedAt: s.endedAt, subTutorId: tutorId)
        }
    }

    func createRetrospectiveSession(
        classId: UUID, sessionDate: String, topic: String?, notes: String?, subTutorId: UUID?
    ) throws -> Session {
        guard sessionDate < todayString else {
            throw DemoModeError.unavailable(String(localized: "Retrospective sessions must be in the past."))
        }
        return try write { d in
            if d.sessions.contains(where: { $0.classId == classId && $0.sessionDate == sessionDate }) {
                throw DemoModeError.unavailable(String(localized: "A session already exists on that date."))
            }
            let created = Session(
                id: UUID(), classId: classId, sessionDate: sessionDate, topic: topic, notes: notes,
                startedAt: nil, endedAt: nil, subTutorId: subTutorId)
            d.sessions.append(created)
            return created
        }
    }

    func updateRetrospectiveSession(
        sessionId: UUID, topic: String?, notes: String?, subTutorId: UUID?
    ) throws -> Session {
        try updateSession(sessionId) { s in
            Session(id: s.id, classId: s.classId, sessionDate: s.sessionDate, topic: topic,
                    notes: notes, startedAt: s.startedAt, endedAt: s.endedAt, subTutorId: subTutorId)
        }
        return try read { d in
            guard let s = d.sessions.first(where: { $0.id == sessionId }) else { throw DemoModeError.notFound("session") }
            return s
        }
    }

    // MARK: - Roster & attendance

    func fetchRoster(sessionId: UUID) throws -> [RosterEntry] {
        try read { d in
            guard let session = d.sessions.first(where: { $0.id == sessionId }) else {
                throw DemoModeError.notFound("session")
            }
            let enrolled = Set(d.enrollments.filter { $0.classId == session.classId && $0.isActive }.map(\.studentId))
            let rows = d.attendance.filter { $0.sessionId == sessionId }
            // Students with a row stay visible even if later unenrolled (matches the RPC).
            let ids = enrolled.union(rows.map(\.studentId))
            return d.students
                .filter { student in
                    ids.contains(student.id) && (student.isActive || rows.contains { $0.studentId == student.id })
                }
                .sorted { $0.fullName < $1.fullName }
                .map { student -> RosterEntry in
                    let row = rows.first { $0.studentId == student.id }
                    return RosterEntry(
                        studentId: student.id, fullName: student.fullName, status: row?.status,
                        markedAt: row?.markedAt, absenceInformed: row?.absenceInformed,
                        observedMarkedAtRaw: row.map { Self.isoFractional.string(from: $0.markedAt) },
                        avatarUrl: student.avatarUrl)
                }
        }
    }

    func loadStudySpace() throws -> (session: Session, roster: [RosterEntry]) {
        let session = getOrCreateTodaySession(classId: AttendanceService.studySpaceClassId)
        let roster: [RosterEntry] = read { d in
            let rows = d.attendance.filter { $0.sessionId == session.id }
            return d.students.filter(\.isActive).sorted { $0.fullName < $1.fullName }.map { student -> RosterEntry in
                let row = rows.first { $0.studentId == student.id }
                return RosterEntry(
                    studentId: student.id, fullName: student.fullName, status: row?.status,
                    markedAt: row?.markedAt, absenceInformed: nil,
                    observedMarkedAtRaw: row.map { Self.isoFractional.string(from: $0.markedAt) },
                    avatarUrl: student.avatarUrl)
            }
        }
        return (session, roster)
    }

    @discardableResult
    func markAttendance(
        sessionId: UUID, studentId: UUID, status: AttendanceStatus,
        notes: String? = nil, lateReason: String? = nil, absenceInformed: Bool? = nil,
        markedAt explicitMarkedAt: Date? = nil
    ) throws -> AttendanceWriteReceipt {
        let markedAt = explicitMarkedAt ?? now
        let _: String = try write { d in
            guard let session = d.sessions.first(where: { $0.id == sessionId }) else {
                throw DemoModeError.notFound("session")
            }
            if session.endedAt != nil, session.sessionDate == todayString {
                throw DemoModeError.unavailable(String(localized: "This class has ended. Attendance is locked."))
            }
            guard let student = d.students.first(where: { $0.id == studentId }) else {
                throw DemoModeError.notFound("student")
            }
            let informed = status == .absent ? absenceInformed : nil
            if let i = d.attendance.firstIndex(where: { $0.sessionId == sessionId && $0.studentId == studentId }) {
                d.attendance[i].status = status
                d.attendance[i].markedAt = markedAt
                d.attendance[i].notes = notes
                d.attendance[i].lateReason = status == .late ? lateReason : nil
                d.attendance[i].absenceInformed = informed
            } else {
                d.attendance.append(DemoAttendanceRow(
                    id: UUID(), sessionId: sessionId, studentId: studentId, status: status,
                    markedAt: markedAt, notes: notes,
                    lateReason: status == .late ? lateReason : nil, absenceInformed: informed))
            }
            return student.fullName
        }
        return AttendanceWriteReceipt(markedAt: Self.isoFractional.string(from: markedAt))
    }

    /// "Not Here Yet" is the absence of a row.
    func clearAttendance(sessionId: UUID, studentId: UUID) {
        write { d in d.attendance.removeAll { $0.sessionId == sessionId && $0.studentId == studentId } }
    }

    func markRetrospectiveAttendance(
        sessionId: UUID, studentId: UUID, status: AttendanceStatus?, absenceInformed: Bool?
    ) throws {
        guard let status else {
            clearAttendance(sessionId: sessionId, studentId: studentId)
            return
        }
        let sessionDate = read { d in d.sessions.first { $0.id == sessionId }?.sessionDate }
        let cal = AttendanceService.singaporeCalendar
        let day = sessionDate.flatMap { AttendanceService.ymdFormatter.date(from: $0) } ?? now
        let markedAt = cal.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? day
        try markAttendance(
            sessionId: sessionId, studentId: studentId, status: status,
            absenceInformed: absenceInformed, markedAt: markedAt)
    }

    func syncPending(_ records: [PendingAttendanceRecord]) throws -> (
        synced: Int, skipped: Int, blockedEndedSession: Int, skippedConflict: Int
    ) {
        var synced = 0
        for record in records {
            if let status = record.status {
                try markAttendance(
                    sessionId: record.sessionId, studentId: record.studentId, status: status,
                    notes: record.notes, absenceInformed: record.absenceInformed)
            } else {
                clearAttendance(sessionId: record.sessionId, studentId: record.studentId)
            }
            synced += 1
        }
        return (synced, 0, 0, 0)
    }

    func fetchStudentAttendanceHistory(studentId: UUID, limit: Int, since: Date?) -> [AttendanceHistoryRecord] {
        let sinceString = since.map { AttendanceService.ymdFormatter.string(from: $0) }
        let records: [AttendanceHistoryRecord] = read { d in
            let sessions = Dictionary(uniqueKeysWithValues: d.sessions.map { ($0.id, $0) })
            let classes = Dictionary(uniqueKeysWithValues: d.classes.map { ($0.id, $0) })
            return d.attendance
                .filter { $0.studentId == studentId }
                .compactMap { row -> (DemoAttendanceRow, Session, TAVClass)? in
                    guard let s = sessions[row.sessionId], let c = classes[s.classId] else { return nil }
                    // Study Space is internal-only and never appears in history.
                    guard c.isStudySpace != true else { return nil }
                    if let sinceString, s.sessionDate < sinceString { return nil }
                    return (row, s, c)
                }
                .sorted { $0.0.markedAt > $1.0.markedAt }
                .prefix(limit)
                .map { item -> AttendanceHistoryRecord in
                    let (row, s, c) = item
                    return AttendanceHistoryRecord(
                        id: row.id, status: row.status, markedAt: row.markedAt,
                        absenceInformed: row.absenceInformed,
                        session: .init(sessionDate: s.sessionDate, class: .init(name: c.name)))
                }
        }
        return records
    }

    func fetchClassPunctuality(classId: UUID, from: Date, to: Date) -> PunctualitySummary {
        let fromString = AttendanceService.ymdFormatter.string(from: from)
        let toString = AttendanceService.ymdFormatter.string(from: to)
        return read { d in
            let sessionIds = Set(d.sessions.filter {
                $0.classId == classId && $0.sessionDate >= fromString && $0.sessionDate <= toString
            }.map(\.id))
            let rows = d.attendance.filter { sessionIds.contains($0.sessionId) }
            let present = rows.filter { $0.status == .present }.count
            let late = rows.filter { $0.status == .late }.count
            let absent = rows.filter { $0.status == .absent }.count
            let total = rows.count
            let attended = present + late
            return PunctualitySummary(
                presentCount: present, lateCount: late, absentCount: absent, totalCount: total,
                onTimeRate: attended == 0 ? nil : Double(present) / Double(attended))
        }
    }

    func fetchAttendanceForExport(classId: UUID, from: Date, to: Date) -> [AttendanceExportRecord] {
        let fromString = AttendanceService.ymdFormatter.string(from: from)
        let toString = AttendanceService.ymdFormatter.string(from: to)
        return read { d in
            let sessions = Dictionary(uniqueKeysWithValues: d.sessions.map { ($0.id, $0) })
            return d.attendance.compactMap { row -> AttendanceExportRecord? in
                guard let s = sessions[row.sessionId], s.classId == classId,
                      s.sessionDate >= fromString, s.sessionDate <= toString else { return nil }
                return AttendanceExportRecord(
                    studentId: row.studentId, status: row.status, markedAt: row.markedAt,
                    lateReason: row.lateReason, session: .init(sessionDate: s.sessionDate))
            }
            .sorted { $0.sessionDate < $1.sessionDate }
        }
    }

    // MARK: - Dismissals

    func recordDismissal(sessionId: UUID, studentId: UUID) -> Dismissal {
        let at = now
        return write { d in
            d.dismissals.removeAll { $0.sessionId == sessionId && $0.studentId == studentId }
            let row = Dismissal(
                id: UUID(), sessionId: sessionId, studentId: studentId, dismissedAt: at,
                dismissedBy: DemoMode.userId, safelyHomeAt: nil)
            d.dismissals.append(row)
            return row
        }
    }

    func undoDismissal(sessionId: UUID, studentId: UUID) {
        write { d in d.dismissals.removeAll { $0.sessionId == sessionId && $0.studentId == studentId } }
    }

    func fetchTodaysDismissals(sessionIds: [UUID]) -> [UUID: Dismissal] {
        let ids = Set(sessionIds)
        let rows = read { d in d.dismissals.filter { row in row.sessionId.map { ids.contains($0) } ?? false } }
        return AttendanceService.latestDismissalsByStudent(rows)
    }

    func fetchTodayDismissals() -> [Dismissal] { read { $0.dismissals } }

    func markSafelyHome(dismissalId: UUID) {
        let at = now
        write { d in
            guard let i = d.dismissals.firstIndex(where: { $0.id == dismissalId }) else { return }
            let old = d.dismissals[i]
            d.dismissals[i] = Dismissal(
                id: old.id, sessionId: old.sessionId, studentId: old.studentId,
                dismissedAt: old.dismissedAt, dismissedBy: old.dismissedBy, safelyHomeAt: old.safelyHomeAt ?? at)
        }
    }

    // MARK: - Parent portal & messages

    func fetchResultSlips(studentId: UUID) -> [ResultSlip] {
        read { d in
            d.resultSlips.filter { $0.studentId == studentId }
                .sorted { ($0.uploadedAt ?? .distantPast) > ($1.uploadedAt ?? .distantPast) }
        }
    }

    func createResultSlip(
        studentId: UUID, examName: String?, examDate: String?, subject: String?,
        score: Double?, maxScore: Double?
    ) -> ResultSlip {
        let row = ResultSlip(
            id: UUID(), studentId: studentId, examName: examName, examDate: examDate,
            subject: subject, score: score, maxScore: maxScore, uploadedAt: now, acknowledgedAt: nil)
        write { $0.resultSlips.append(row) }
        return row
    }

    func fetchMessages(studentId: UUID) -> [ParentMessage] {
        read { d in
            d.messages.filter { $0.studentId == studentId }
                .sorted { ($0.sentAt ?? .distantPast) < ($1.sentAt ?? .distantPast) }
        }
    }

    func sendMessage(studentId: UUID, subject: String?, body: String) -> ParentMessage {
        let row = ParentMessage(
            id: UUID(), senderId: DemoMode.userId, recipientId: nil, studentId: studentId,
            subject: subject, body: body, sentAt: now, readAt: nil, parentOrigin: false)
        write { $0.messages.append(row) }
        return row
    }

    func fetchParents() -> [Profile] {
        read { d in d.profiles.filter { $0.role == "parent" }.sorted { $0.fullName < $1.fullName } }
    }

    func fetchParentLinks(parentId: UUID) -> [UUID] {
        read { d in d.parentLinks.filter { $0.parentId == parentId }.map(\.studentId) }
    }

    func linkParent(parentId: UUID, studentId: UUID) {
        write { d in
            let link = DemoParentLink(parentId: parentId, studentId: studentId)
            if !d.parentLinks.contains(link) { d.parentLinks.append(link) }
        }
    }

    func unlinkParent(parentId: UUID, studentId: UUID) {
        write { d in d.parentLinks.removeAll { $0.parentId == parentId && $0.studentId == studentId } }
    }

    // MARK: - Privacy

    func fetchPrivacyNotice() -> PolicyDocument { read { $0.privacyNotice } }

    func recordConsent(studentId: UUID, consentType: String, status: ConsentStatus) {
        let at = now
        write { d in
            d.consents.removeAll { $0.studentId == studentId && $0.consentType == consentType }
            d.consents.append(ConsentRecord(
                studentId: studentId, consentType: consentType, status: status,
                method: "admin_attested", noticeVersion: d.privacyNotice.version,
                grantedBy: DemoMode.userId, parentId: nil, createdAt: at))
        }
    }

    func fetchCurrentConsent(studentId: UUID) -> [ConsentRecord] {
        read { d in d.consents.filter { $0.studentId == studentId } }
    }

    func exportStudentPersonalData(id: UUID) throws -> Data {
        let bundle: [String: Any] = try read { d in
            guard let s = d.students.first(where: { $0.id == id }) else { throw DemoModeError.notFound("student") }
            let rows = d.attendance.filter { $0.studentId == id }
            return [
                "student": [
                    "id": s.id.uuidString.lowercased(),
                    "full_name": s.fullName,
                    "school": s.school.map { $0 as Any } ?? NSNull(),
                    "year_of_study": s.yearOfStudy.map { $0 as Any } ?? NSNull(),
                ] as [String: Any],
                "attendance_count": rows.count,
                "generated_at": Self.isoFractional.string(from: now),
            ]
        }
        return try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
    }

    func fetchCorrectionRequests(status: CorrectionStatus) -> [CorrectionRequest] {
        read { d in
            d.corrections.filter { $0.status == status }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    func reviewCorrection(id: UUID, decision: CorrectionStatus, note: String?) throws {
        let at = now
        try write { d in
            guard let i = d.corrections.firstIndex(where: { $0.id == id }) else {
                throw DemoModeError.notFound("correction request")
            }
            let r = d.corrections[i]
            d.corrections[i] = CorrectionRequest(
                id: r.id, studentId: r.studentId, requestedBy: r.requestedBy, fieldName: r.fieldName,
                currentValue: r.currentValue, requestedValue: r.requestedValue, status: decision,
                reviewedBy: DemoMode.userId, reviewedAt: at, reviewNote: note, createdAt: r.createdAt)
            guard decision == .applied, let s = d.students.firstIndex(where: { $0.id == r.studentId }) else { return }
            let old = d.students[s]
            let value = r.requestedValue
            d.students[s] = Student(
                id: old.id,
                fullName: r.fieldName == "full_name" ? (value ?? old.fullName) : old.fullName,
                school: r.fieldName == "school" ? value : old.school,
                yearOfStudy: r.fieldName == "year_of_study" ? value : old.yearOfStudy,
                isActive: old.isActive, avatarUrl: old.avatarUrl)
        }
    }
}

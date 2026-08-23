import AppIntents
import XCTest
import CryptoKit
@testable import TAVAttendance

final class AttendanceLogicTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    @MainActor
    func testKioskPINBlocksAppIntentsUntilCurrentLaunchUnlock() {
        XCTAssertFalse(KioskSecurityState.allowsAppIntents(
            hasConfiguredPIN: true, isAdminUnlocked: false))
        XCTAssertTrue(KioskSecurityState.allowsAppIntents(
            hasConfiguredPIN: true, isAdminUnlocked: true))
        XCTAssertTrue(KioskSecurityState.allowsAppIntents(
            hasConfiguredPIN: false, isAdminUnlocked: false))
        XCTAssertFalse(KioskSecurityState.allowsSensitiveEntityQueries(isAdminUnlocked: false))
        XCTAssertTrue(KioskSecurityState.allowsSensitiveEntityQueries(isAdminUnlocked: true))
    }

    func testLockedKioskOnlyAuthorizesStudentSignIn() {
        XCTAssertTrue(GlobalKioskView.isActionAuthorized(.signIn, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markLate, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markPresent, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markAbsent(informed: false), isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.clearAttendance, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markDismissed, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.undoDismissal, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.addLateReason("traffic"), isAdminMode: false))
        XCTAssertTrue(GlobalKioskView.isActionAuthorized(.markAbsent(informed: true), isAdminMode: true))
    }

    func testMalformedStoredPINRequiresAuthenticatedReset() {
        XCTAssertEqual(storedKioskPINDisposition(""), .none)
        XCTAssertEqual(storedKioskPINDisposition("1234"), .legacyPlaintext)
        XCTAssertEqual(storedKioskPINDisposition("v1:" + String(repeating: "a", count: 64)), .currentHash)
        XCTAssertEqual(storedKioskPINDisposition("v1:not-a-hash"), .requiresAuthenticatedReset)
        XCTAssertEqual(storedKioskPINDisposition("corrupt"), .requiresAuthenticatedReset)
    }

    func testConfiguredKioskStartsLocked() {
        XCTAssertTrue(shouldLockKioskOnStart(storedPIN: "v1:" + String(repeating: "a", count: 64)))
        XCTAssertTrue(shouldLockKioskOnStart(storedPIN: "1234"))
        XCTAssertFalse(shouldLockKioskOnStart(storedPIN: ""))
    }

    func testAdminAuthorizationPermitsOverridesAndDismissals() {
        let adminActions: [GlobalKioskView.KioskAction] = [
            .markLate, .markPresent, .markAbsent(informed: false), .clearAttendance,
            .markDismissed, .undoDismissal, .addLateReason("traffic"),
        ]
        for action in adminActions {
            XCTAssertTrue(isKioskActionAuthorized(action, isAdminMode: true), "\(action)")
            XCTAssertFalse(isKioskActionAuthorized(action, isAdminMode: false), "\(action)")
        }
        XCTAssertTrue(isKioskActionAuthorized(.signIn, isAdminMode: false))
        XCTAssertTrue(isKioskActionAuthorized(.signIn, isAdminMode: true))
    }

    func testActiveLockoutRejectsCorrectPINWithoutChangingState() {
        let state = KioskPINLockoutState(failedAttempts: 0, lockoutUntil: 40_000)
        let (next, result) = evaluateKioskPINAttempt(pinMatches: true, state: state, now: 10_000)
        XCTAssertTrue(isKioskUnlockBlocked(lockoutUntil: state.lockoutUntil, now: 10_000))
        XCTAssertEqual(next, state)
        XCTAssertEqual(result, .lockedOut(until: 40_000))
    }

    func testFiveFailuresEnterEscalatingLockoutWindows() {
        var state = KioskPINLockoutState()
        var result: KioskPINAttemptResult = .unlocked
        let now: TimeInterval = 10_000
        for _ in 0..<5 {
            (state, result) = evaluateKioskPINAttempt(pinMatches: false, state: state, now: now)
        }
        XCTAssertEqual(state.failedAttempts, 5)
        XCTAssertEqual(state.lockoutUntil, now + 30)
        XCTAssertEqual(result, .lockedOut(until: now + 30))

        // After the window expires, another wrong entry escalates (6 failures → 60s).
        let afterFirstWindow = state.lockoutUntil
        (state, result) = evaluateKioskPINAttempt(
            pinMatches: false,
            state: state,
            now: afterFirstWindow
        )
        XCTAssertEqual(state.failedAttempts, 6)
        XCTAssertEqual(result, .lockedOut(until: afterFirstWindow + 60))
        XCTAssertEqual(state.lockoutUntil, afterFirstWindow + 60)
    }

    func testSuccessfulAuthenticationResetsLockoutState() {
        let state = KioskPINLockoutState(failedAttempts: 4, lockoutUntil: 0)
        let (next, result) = evaluateKioskPINAttempt(pinMatches: true, state: state, now: 10_000)
        XCTAssertEqual(next, KioskPINLockoutState())
        XCTAssertEqual(result, .unlocked)
    }

    func testIncorrectPINReportsRemainingAttempts() {
        let (state, result) = evaluateKioskPINAttempt(
            pinMatches: false,
            state: KioskPINLockoutState(),
            now: 10_000
        )
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(result, .incorrect(attemptsRemaining: 4))
    }

    @MainActor
    func testBackgroundingRevokesProcessLocalAdminAuthorization() {
        let security = KioskSecurityState.shared
        security.isAdminUnlocked = true
        // Simulate a configured PIN for the shared process-local gate.
        UserDefaults.standard.set("v1:" + String(repeating: "b", count: 64), forKey: "kioskPIN")
        defer {
            security.isAdminUnlocked = false
            UserDefaults.standard.removeObject(forKey: "kioskPIN")
        }
        security.relockIfConfigured()
        XCTAssertFalse(security.isAdminUnlocked)
    }

    func testConstantTimeHexEquality() {
        XCTAssertTrue(constantTimeEqualHex("v1:abcd", "v1:abcd"))
        XCTAssertFalse(constantTimeEqualHex("v1:abcd", "v1:abce"))
        XCTAssertFalse(constantTimeEqualHex("v1:ab", "v1:abcd"))
    }

    func testLockoutDurationEscalatesAndCaps() {
        XCTAssertEqual(kioskLockoutDuration(forFailures: 5), 30)
        XCTAssertEqual(kioskLockoutDuration(forFailures: 6), 60)
        XCTAssertEqual(kioskLockoutDuration(forFailures: 7), 120)
        XCTAssertEqual(kioskLockoutDuration(forFailures: 100), 3600)
    }

    func testAttendanceAppIntentsRequireLocalDeviceAuthentication() {
        let protectedPolicies: [IntentAuthenticationPolicy] = [
            SignInStudentIntent.authenticationPolicy,
            MarkAttendanceIntent.authenticationPolicy,
            CheckStudentStatusIntent.authenticationPolicy,
            TodayAttendanceSummaryIntent.authenticationPolicy,
            StudentAttendanceRateIntent.authenticationPolicy,
            ClassPunctualityIntent.authenticationPolicy,
        ]
        XCTAssertTrue(protectedPolicies.allSatisfy { $0 == .requiresLocalDeviceAuthentication })
        XCTAssertEqual(OpenKioskIntent.authenticationPolicy, .alwaysAllowed)
    }

    func testPrivacyShieldCoversEveryNonActiveScenePhase() {
        XCTAssertFalse(shouldShowPrivacyShield(for: .active))
        XCTAssertTrue(shouldShowPrivacyShield(for: .inactive))
        XCTAssertTrue(shouldShowPrivacyShield(for: .background))
    }

    func testCSVCellsNeutralizeSpreadsheetFormulas() {
        XCTAssertEqual(escapedCSVCell("=2+3"), "'=2+3")
        XCTAssertEqual(escapedCSVCell("+1+1"), "'+1+1")
        XCTAssertEqual(escapedCSVCell("-2+3"), "'-2+3")
        XCTAssertEqual(escapedCSVCell("@SUM(A1:A2)"), "'@SUM(A1:A2)")
        XCTAssertEqual(escapedCSVCell("\t=1+1"), "'\t=1+1")
        XCTAssertEqual(escapedCSVCell("\r=1+1"), "\"'\r=1+1\"")
        XCTAssertEqual(escapedCSVCell("\n=1+1"), "\"'\n=1+1\"")
    }

    func testCSVCellsStillApplyRFC4180Escaping() {
        XCTAssertEqual(escapedCSVCell("Doe, Jane"), "\"Doe, Jane\"")
        XCTAssertEqual(escapedCSVCell("Jane \"JJ\" Doe"), "\"Jane \"\"JJ\"\" Doe\"")
        XCTAssertEqual(escapedCSVCell("ordinary text"), "ordinary text")
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 10
        c.hour = hour; c.minute = minute; c.second = 0
        return calendar.date(from: c)!
    }

    // MARK: signInStatus

    func testScheduleTimeParsesBothFormats() {
        let now = at(20, 30)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "20:00:00", startedAt: nil, now: now, calendar: calendar), .late)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "20:00", startedAt: nil, now: now, calendar: calendar), .late)
    }

    func testTimeInFutureIsPresent() {
        let now = at(19, 30)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "20:00:00", startedAt: nil, now: now, calendar: calendar), .present)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "20:00", startedAt: nil, now: now, calendar: calendar), .present)
    }

    func testStartedAtInPastForcesLateRegardlessOfSchedule() {
        let now = at(19, 30)
        let started = at(19, 0)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "23:00:00", startedAt: started, now: now, calendar: calendar), .late)
    }

    func testStartedAtInFutureDoesNotForceLate() {
        let now = at(19, 30)
        let started = at(20, 0)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: nil, startedAt: started, now: now, calendar: calendar), .present)
    }

    func testNilScheduleAndNilStartedIsPresent() {
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: nil, startedAt: nil, now: at(20, 0), calendar: calendar), .present)
    }

    func testMalformedScheduleFallsThroughToPresent() {
        let now = at(20, 30)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "garbage", startedAt: nil, now: now, calendar: calendar), .present)
        XCTAssertEqual(AttendanceService.signInStatus(scheduleTime: "20", startedAt: nil, now: now, calendar: calendar), .present)
    }

    func testSingaporeMondayMorningIsMondayAndNotLateAgainstEveningSchedule() {
        var singapore = Calendar(identifier: .gregorian)
        singapore.timeZone = TimeZone(identifier: "Asia/Singapore")!
        // Monday 07:00 SGT = Sunday 23:00 UTC. Device TZ must not win.
        let mondayMorning = singapore.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 7, minute: 0, second: 0))!
        let mondayEvening = singapore.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 19, minute: 30, second: 0))!

        XCTAssertEqual(AttendanceService.weekdayName(for: mondayMorning), "Monday")
        XCTAssertEqual(
            AttendanceService.signInStatus(scheduleTime: "19:00:00", startedAt: nil, now: mondayMorning),
            .present
        )
        XCTAssertEqual(
            AttendanceService.signInStatus(scheduleTime: "19:00", startedAt: nil, now: mondayEvening),
            .late
        )
        XCTAssertEqual(
            AttendanceService.ymdFormatter.string(from: mondayMorning),
            "2026-08-24"
        )
    }

    // MARK: worstStatus

    func testWorstStatusRanking() {
        XCTAssertEqual(AttendanceService.worstStatus(.late, .present), .late)
        XCTAssertEqual(AttendanceService.worstStatus(.present, .absent), .present)
    }

    func testWorstStatusNilHandling() {
        XCTAssertEqual(AttendanceService.worstStatus(nil, .absent), .absent)
        XCTAssertEqual(AttendanceService.worstStatus(.late, nil), .late)
        XCTAssertNil(AttendanceService.worstStatus(nil, nil))
    }

    func testWorstStatusEqual() {
        XCTAssertEqual(AttendanceService.worstStatus(.present, .present), .present)
    }

    // MARK: classMeetsToday

    private func makeClass(recurrenceRule: String? = nil, scheduleDay: String? = nil) -> TAVClass {
        TAVClass(id: UUID(), name: "Test", subject: nil, level: nil,
                 scheduleDay: scheduleDay, scheduleTime: nil, durationMinutes: 60,
                 isActive: true, recurrenceRule: recurrenceRule,
                 recurrenceEndDate: nil, isStudySpace: nil,
                 canManageSessions: nil, canOperateTodaySession: nil)
    }

    func testBydayRuleMatchesWeekday() {
        let cls = makeClass(recurrenceRule: "FREQ=WEEKLY;BYDAY=MO,TH")
        XCTAssertTrue(AttendanceService.classMeetsToday(cls, weekday: "Monday"))
        XCTAssertTrue(AttendanceService.classMeetsToday(cls, weekday: "Thursday"))
        XCTAssertFalse(AttendanceService.classMeetsToday(cls, weekday: "Saturday"))
    }

    func testBydayRuleWinsOverScheduleDay() {
        let cls = makeClass(recurrenceRule: "FREQ=WEEKLY;BYDAY=MO", scheduleDay: "Saturday")
        XCTAssertFalse(AttendanceService.classMeetsToday(cls, weekday: "Saturday"))
        XCTAssertTrue(AttendanceService.classMeetsToday(cls, weekday: "Monday"))
    }

    func testScheduleDayMatchIsCaseInsensitive() {
        let cls = makeClass(scheduleDay: "thursday")
        XCTAssertTrue(AttendanceService.classMeetsToday(cls, weekday: "Thursday"))
        XCTAssertFalse(AttendanceService.classMeetsToday(cls, weekday: "Monday"))
    }

    func testAdHocClassAlwaysMeets() {
        let cls = makeClass()
        XCTAssertTrue(AttendanceService.classMeetsToday(cls, weekday: "Saturday"))
        XCTAssertTrue(AttendanceService.classMeetsToday(cls, weekday: "Sunday"))
    }

    // MARK: subject normalization (student results / class form)

    func testSubjectNormalization() {
        XCTAssertEqual(ResultSlipSubject(normalizing: "Math"), .math)
        XCTAssertEqual(ResultSlipSubject(normalizing: "Mathematics "), .math)
        XCTAssertEqual(ResultSlipSubject(normalizing: "english"), .english)
        XCTAssertEqual(ResultSlipSubject(normalizing: "English "), .english)
        XCTAssertNil(ResultSlipSubject(normalizing: "Science"))
        XCTAssertNil(ResultSlipSubject(normalizing: nil))
        XCTAssertNil(ResultSlipSubject(normalizing: ""))
    }

    // MARK: primary/secondary grade-band inference

    private func student(year: String?) -> Student {
        Student(id: UUID(), fullName: "Test", school: nil, yearOfStudy: year,
                isActive: true, avatarUrl: nil)
    }

    func testPrimaryLevelInference() {
        XCTAssertEqual(student(year: "P5").isPrimaryLevel, true)
        XCTAssertEqual(student(year: "Primary 4").isPrimaryLevel, true)
        XCTAssertEqual(student(year: "Sec 2").isPrimaryLevel, false)
        XCTAssertEqual(student(year: "sec 2 but he doesn’t study").isPrimaryLevel, false)
        XCTAssertNil(student(year: "3").isPrimaryLevel)
        XCTAssertNil(student(year: nil).isPrimaryLevel)
    }

    // MARK: QR payload → student UUID

    func testQRPayloadParsing() {
        let id = UUID()
        XCTAssertEqual(AttendanceService.studentId(fromQRPayload: id.uuidString), id)
        XCTAssertEqual(AttendanceService.studentId(fromQRPayload: " \(id.uuidString.lowercased())\n"), id)
        XCTAssertNil(AttendanceService.studentId(fromQRPayload: ""))
        XCTAssertNil(AttendanceService.studentId(fromQRPayload: "not-a-uuid"))
        XCTAssertNil(AttendanceService.studentId(fromQRPayload: "https://example.com/\(id.uuidString)"))
    }

    // MARK: safely-home filter (migration 030, flag: push_notifications)

    private func dismissal(studentId: UUID = UUID(), dismissedAt: Date?, safelyHomeAt: Date?) -> Dismissal {
        Dismissal(id: UUID(), sessionId: UUID(), studentId: studentId,
                  dismissedAt: dismissedAt, dismissedBy: nil, safelyHomeAt: safelyHomeAt)
    }

    func testAwaitingSafelyHome() {
        let confirmed = dismissal(dismissedAt: at(9, 0), safelyHomeAt: at(9, 30))
        let awaiting = dismissal(dismissedAt: at(9, 0), safelyHomeAt: nil)
        let noTimestamp = dismissal(dismissedAt: nil, safelyHomeAt: nil)
        let result = AttendanceService.awaitingSafelyHome([confirmed, awaiting, noTimestamp])
        XCTAssertEqual(result.map(\.id), [awaiting.id])
    }

    func testLatestDismissalWinsWhenStudentHasMultipleSessions() {
        let studentId = UUID()
        let earlier = dismissal(studentId: studentId, dismissedAt: at(9, 0), safelyHomeAt: nil)
        let later = dismissal(studentId: studentId, dismissedAt: at(10, 0), safelyHomeAt: nil)

        XCTAssertEqual(AttendanceService.latestDismissalsByStudent([earlier, later])[studentId]?.id, later.id)
    }

    func testPushNotificationsDisabledHidesDismissals() {
        let awaiting = dismissal(dismissedAt: at(9, 0), safelyHomeAt: nil)
        XCTAssertTrue(ParentDismissalVisibility.visible(
            pushNotificationsEnabled: false,
            dismissals: [awaiting]
        ).isEmpty)
    }

    // MARK: offline queue account binding

    private func pendingRecord(
        ownerUserId: UUID,
        mutationId: String = "pending",
        status: AttendanceStatus? = .present,
        observedMarkedAt: Date? = nil,
        didObserveRow: Bool = false
    ) -> PendingAttendanceRecord {
        PendingAttendanceRecord(
            ownerUserId: ownerUserId,
            sessionId: UUID(),
            studentId: UUID(),
            status: status,
            notes: nil,
            absenceInformed: nil,
            clientMutationId: mutationId,
            markedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isSynced: false,
            observedMarkedAt: observedMarkedAt,
            didObserveRow: didObserveRow
        )
    }

    func testPendingQueueRoundTripRequiresMatchingEnvelopeAndRecordOwner() throws {
        let owner = UUID()
        let foreignOwner = UUID()
        let data = try XCTUnwrap(PendingAttendanceQueueCodec.encode(
            ownerUserId: owner,
            records: [pendingRecord(ownerUserId: owner)]
        ))

        XCTAssertEqual(
            PendingAttendanceQueueCodec.decode(data, expectedOwnerUserId: owner)?.map(\.clientMutationId),
            ["pending"]
        )
        XCTAssertNil(PendingAttendanceQueueCodec.decode(data, expectedOwnerUserId: foreignOwner))
    }

    func testPendingClearRoundTripsAndSyncPayloadEncodesNullStatus() throws {
        let owner = UUID()
        let record = pendingRecord(ownerUserId: owner, status: nil)
        let data = try XCTUnwrap(PendingAttendanceQueueCodec.encode(
            ownerUserId: owner, records: [record]))
        let decoded = try XCTUnwrap(PendingAttendanceQueueCodec.decode(
            data, expectedOwnerUserId: owner))
        XCTAssertNil(try XCTUnwrap(decoded.first).status)

        let payload = SyncAttendancePayload(
            sessionId: record.sessionId,
            studentId: record.studentId,
            status: nil,
            notes: "",
            clientMutationId: record.clientMutationId,
            markedAt: ISO8601DateFormatter().string(from: record.markedAt),
            absenceInformed: nil
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertTrue(object["status"] is NSNull)
    }

    func testPendingQueueMigratesVersionTwoStatusesGenerically() throws {
        struct LegacyRecord: Codable {
            let ownerUserId: UUID
            let sessionId: UUID
            let studentId: UUID
            let status: String
            let notes: String?
            let clientMutationId: String
            let markedAt: Date
            let isSynced: Bool
        }
        struct LegacyEnvelope: Codable {
            let version: Int
            let ownerUserId: UUID
            let records: [LegacyRecord]
        }

        let owner = UUID()
        let base = pendingRecord(ownerUserId: owner)
        let records = [
            LegacyRecord(
                ownerUserId: owner, sessionId: base.sessionId, studentId: base.studentId,
                status: "present", notes: nil, clientMutationId: "known",
                markedAt: base.markedAt, isSynced: false),
            LegacyRecord(
                ownerUserId: owner, sessionId: UUID(), studentId: UUID(),
                status: "removed-status", notes: nil, clientMutationId: "clear",
                markedAt: base.markedAt, isSynced: false),
        ]
        let data = try JSONEncoder().encode(
            LegacyEnvelope(version: 2, ownerUserId: owner, records: records))
        let decoded = try XCTUnwrap(PendingAttendanceQueueCodec.decode(
            data, expectedOwnerUserId: owner))
        XCTAssertEqual(decoded.map(\.status), [.present, nil])
        XCTAssertTrue(decoded.allSatisfy { !$0.didObserveRow && $0.observedMarkedAt == nil })
    }

    func testPendingQueueRejectsLegacyAndMixedOwnerData() {
        let owner = UUID()
        let foreign = pendingRecord(
            ownerUserId: UUID(),
            mutationId: "foreign",
            observedMarkedAt: Date(timeIntervalSince1970: 1_700_000_000),
            didObserveRow: true
        )
        XCTAssertNil(PendingAttendanceQueueCodec.decode(Data("[]".utf8), expectedOwnerUserId: owner))
        XCTAssertNil(PendingAttendanceQueueCodec.encode(
            ownerUserId: owner,
            records: [foreign]
        ))
        XCTAssertFalse(PendingAttendanceQueueCodec.recordsBelongToOwner(
            [foreign],
            ownerUserId: owner
        ))
        let mixed = [
            pendingRecord(ownerUserId: owner, mutationId: "ours", didObserveRow: true),
            foreign
        ]
        XCTAssertNil(PendingAttendanceQueueCodec.encode(ownerUserId: owner, records: mixed))
        XCTAssertFalse(PendingAttendanceQueueCodec.recordsBelongToOwner(mixed, ownerUserId: owner))
    }

    func testPendingQueueEncodesObservedMarkedAtNullAndDate() throws {
        let owner = UUID()
        let observed = Date(timeIntervalSince1970: 1_700_000_000)
        let unmarked = pendingRecord(
            ownerUserId: owner, mutationId: "unmarked",
            observedMarkedAt: nil, didObserveRow: true)
        let marked = pendingRecord(
            ownerUserId: owner, mutationId: "marked",
            observedMarkedAt: observed, didObserveRow: true)

        let data = try XCTUnwrap(PendingAttendanceQueueCodec.encode(
            ownerUserId: owner, records: [unmarked, marked]))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 4)
        let rows = try XCTUnwrap(object["records"] as? [[String: Any]])
        XCTAssertTrue(rows[0]["observed_marked_at"] is NSNull)
        XCTAssertFalse(rows[1]["observed_marked_at"] is NSNull)
        XCTAssertNotNil(rows[1]["observed_marked_at"])

        let decoded = try XCTUnwrap(
            PendingAttendanceQueueCodec.decode(data, expectedOwnerUserId: owner))
        XCTAssertEqual(decoded.map(\.clientMutationId), ["unmarked", "marked"])
        XCTAssertEqual(decoded.map(\.didObserveRow), [true, true])
        XCTAssertNil(decoded[0].observedMarkedAt)
        XCTAssertEqual(decoded[1].observedMarkedAt, observed)
    }

    func testPendingQueueVersionThreeOmitsObservedAsUnknown() throws {
        struct V3Record: Codable {
            let ownerUserId: UUID
            let sessionId: UUID
            let studentId: UUID
            let status: AttendanceStatus?
            let notes: String?
            let absenceInformed: Bool?
            let clientMutationId: String
            let markedAt: Date
            let isSynced: Bool
        }
        struct V3Envelope: Codable {
            let version: Int
            let ownerUserId: UUID
            let records: [V3Record]
        }

        let owner = UUID()
        let base = pendingRecord(ownerUserId: owner)
        let data = try JSONEncoder().encode(V3Envelope(
            version: 3,
            ownerUserId: owner,
            records: [
                V3Record(
                    ownerUserId: owner, sessionId: base.sessionId, studentId: base.studentId,
                    status: .present, notes: nil, absenceInformed: nil,
                    clientMutationId: "v3", markedAt: base.markedAt, isSynced: false)
            ]
        ))
        let decoded = try XCTUnwrap(
            PendingAttendanceQueueCodec.decode(data, expectedOwnerUserId: owner))
        XCTAssertEqual(decoded.first?.clientMutationId, "v3")
        XCTAssertEqual(decoded.first?.status, .present)
        XCTAssertFalse(try XCTUnwrap(decoded.first).didObserveRow)
        XCTAssertNil(decoded.first?.observedMarkedAt)
    }

    func testInPlaceCorrectionKeepsObservedMarkedAtAndRotatesMutationId() {
        let originalObserved = Date(timeIntervalSince1970: 1_700_000_000)
        var record = pendingRecord(
            ownerUserId: UUID(),
            mutationId: "old",
            status: .present,
            observedMarkedAt: originalObserved,
            didObserveRow: true
        )
        record.applyCorrection(status: .late, notes: "corrected", absenceInformed: nil)
        XCTAssertEqual(record.observedMarkedAt, originalObserved)
        XCTAssertTrue(record.didObserveRow)
        XCTAssertNotEqual(record.clientMutationId, "old")
        XCTAssertFalse(record.clientMutationId.isEmpty)
        XCTAssertEqual(record.status, .late)
        XCTAssertEqual(record.notes, "corrected")
        XCTAssertFalse(record.isSynced)
    }

    func testPendingQueueEncryptionRejectsTampering() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("private attendance queue".utf8)
        let encrypted = try PendingAttendanceQueueCipher.seal(plaintext, using: key)

        XCTAssertEqual(
            try PendingAttendanceQueueCipher.open(encrypted, using: key),
            plaintext
        )
        var tampered = encrypted
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        XCTAssertThrowsError(try PendingAttendanceQueueCipher.open(tampered, using: key))
    }

    func testParentRpcShapesOmitActorSessionAndStorageFields() throws {
        let parentMessage = try JSONDecoder().decode(
            ParentMessage.self,
            from: Data(#"{"id":"10000000-0000-0000-0000-000000000001","student_id":"20000000-0000-0000-0000-000000000002","subject":null,"body":"Hello","sent_at":null,"read_at":null,"is_from_parent":true}"#.utf8)
        )
        let centreMessage = try JSONDecoder().decode(
            ParentMessage.self,
            from: Data(#"{"id":"30000000-0000-0000-0000-000000000003","student_id":"20000000-0000-0000-0000-000000000002","subject":null,"body":"Reply","sent_at":null,"read_at":null,"is_from_parent":false}"#.utf8)
        )
        let dismissal = try JSONDecoder().decode(
            Dismissal.self,
            from: Data(#"{"id":"40000000-0000-0000-0000-000000000004","student_id":"20000000-0000-0000-0000-000000000002","dismissed_at":null,"safely_home_at":null}"#.utf8)
        )
        let child = try JSONDecoder().decode(
            Student.self,
            from: Data(#"{"id":"20000000-0000-0000-0000-000000000002","full_name":"Child","school":null,"year_of_study":null,"is_active":true}"#.utf8)
        )
        let result = try JSONDecoder().decode(
            ResultSlip.self,
            from: Data(#"{"id":"50000000-0000-0000-0000-000000000005","student_id":"20000000-0000-0000-0000-000000000002","exam_name":"CA1","exam_date":"2026-07-01","subject":"Math","score":9,"max_score":10,"file_path":null,"uploaded_at":null,"acknowledged_at":null}"#.utf8)
        )

        XCTAssertTrue(parentMessage.isFromParent)
        XCTAssertFalse(centreMessage.isFromParent)
        XCTAssertNil(parentMessage.senderId)
        XCTAssertNil(parentMessage.recipientId)
        XCTAssertNil(dismissal.sessionId)
        XCTAssertNil(child.avatarUrl)
        XCTAssertFalse(result.isAcknowledged)
    }

    // MARK: result-slip input validation (native parent portal Phase 2)

    func testResultSlipValidationAcceptsValid() {
        XCTAssertNil(ResultSlipInputValidation.validate(examName: "CA1", score: 25, maxScore: 35))
        XCTAssertNil(ResultSlipInputValidation.validate(examName: "  Mid-year  ", score: 0, maxScore: 100))
    }

    func testResultSlipValidationRejectsEmptyExamName() {
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "  ", score: 10, maxScore: 20),
            .emptyExamName
        )
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "", score: 10, maxScore: 20),
            .emptyExamName
        )
    }

    func testResultSlipValidationRejectsInvalidScores() {
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "CA1", score: -1, maxScore: 20),
            .invalidScore
        )
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "CA1", score: nil, maxScore: 20),
            .invalidScore
        )
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "CA1", score: .nan, maxScore: 20),
            .invalidScore
        )
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "CA1", score: 10, maxScore: 0),
            .invalidMaxScore
        )
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "CA1", score: 10, maxScore: -5),
            .invalidMaxScore
        )
        XCTAssertEqual(
            ResultSlipInputValidation.validate(examName: "CA1", score: 21, maxScore: 20),
            .scoreExceedsMax
        )
    }

    // MARK: retrospective sessions (migration 037)

    private func retrospectiveSession(date: String) -> Session {
        Session(id: UUID(), classId: UUID(), sessionDate: date, topic: nil,
                notes: nil, startedAt: nil, endedAt: Date(), subTutorId: nil)
    }

    func testRetrospectiveDateMustBeBeforeToday() {
        let today = at(12, 0)
        XCTAssertTrue(RetrospectiveSessionRules.isPastDate(at(0, 0).addingTimeInterval(-86_400),
                                                           today: today, calendar: calendar))
        XCTAssertFalse(RetrospectiveSessionRules.isPastDate(at(0, 0),
                                                            today: today, calendar: calendar))
        XCTAssertFalse(RetrospectiveSessionRules.isPastDate(at(0, 0).addingTimeInterval(86_400),
                                                            today: today, calendar: calendar))
    }

    func testRetrospectiveExistingSessionDetectionUsesClassDateList() {
        var singapore = Calendar(identifier: .gregorian)
        singapore.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let target = singapore.date(from: DateComponents(year: 2026, month: 7, day: 10))!
        let expected = retrospectiveSession(date: "2026-07-10")
        let sessions = [retrospectiveSession(date: "2026-07-09"), expected]
        XCTAssertEqual(RetrospectiveSessionRules.existingSession(on: target, in: sessions)?.id,
                       expected.id)
    }

    func testHistoricalEditorRequiresFlagAndPastDate() {
        var singapore = Calendar(identifier: .gregorian)
        singapore.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let today = singapore.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 12))!
        XCTAssertTrue(RetrospectiveSessionRules.editorEnabled(
            for: retrospectiveSession(date: "2026-07-09"), flagEnabled: true, today: today))
        XCTAssertFalse(RetrospectiveSessionRules.editorEnabled(
            for: retrospectiveSession(date: "2026-07-10"), flagEnabled: true, today: today))
        XCTAssertFalse(RetrospectiveSessionRules.editorEnabled(
            for: retrospectiveSession(date: "2026-07-09"), flagEnabled: false, today: today))
    }

    // MARK: Study-space history exclusion (shipped query contract)

    func testStudentAttendanceHistoryQueryExcludesStudySpace() {
        XCTAssertTrue(
            StudentAttendanceHistoryQuery.excludesStudySpace,
            "staff history select/filter must drop study-space classes"
        )
        XCTAssertTrue(
            StudentAttendanceHistoryQuery.select.contains("is_study_space"),
            "select must embed is_study_space so the filter can bind"
        )
        XCTAssertEqual(
            StudentAttendanceHistoryQuery.studySpaceFilterColumn,
            "session.class.is_study_space"
        )
        XCTAssertFalse(StudentAttendanceHistoryQuery.studySpaceFilterValue)
    }

    // MARK: - absence_informed sync payload encoding

    func testSyncAttendancePayloadEncodesAbsenceInformed() throws {
        let withFlag = SyncAttendancePayload(
            sessionId: UUID(), studentId: UUID(), status: .absent,
            notes: "", clientMutationId: "m1",
            markedAt: "2026-08-06T00:00:00Z", absenceInformed: true)
        let data = try JSONEncoder().encode(withFlag)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["absence_informed"] as? Bool, true)

        let withoutFlag = SyncAttendancePayload(
            sessionId: UUID(), studentId: UUID(), status: .absent,
            notes: "", clientMutationId: "m2",
            markedAt: "2026-08-06T00:00:00Z", absenceInformed: nil)
        let data2 = try JSONEncoder().encode(withoutFlag)
        let obj2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]
        XCTAssertNil(obj2["absence_informed"])
    }

    func testSyncAttendancePayloadEncodesObservedMarkedAt() throws {
        let withDate = SyncAttendancePayload(
            sessionId: UUID(), studentId: UUID(), status: .present,
            notes: "", clientMutationId: "m1",
            markedAt: "2026-08-24T11:00:00Z", absenceInformed: nil,
            observedMarkedAt: "2026-08-24T10:55:00Z", didObserveRow: true)
        let withDateObj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(withDate)) as! [String: Any]
        XCTAssertEqual(withDateObj["observed_marked_at"] as? String, "2026-08-24T10:55:00Z")

        let unmarked = SyncAttendancePayload(
            sessionId: UUID(), studentId: UUID(), status: .present,
            notes: "", clientMutationId: "m2",
            markedAt: "2026-08-24T11:00:00Z", absenceInformed: nil,
            observedMarkedAt: nil, didObserveRow: true)
        let unmarkedObj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(unmarked)) as! [String: Any]
        XCTAssertTrue(unmarkedObj["observed_marked_at"] is NSNull)

        let unknown = SyncAttendancePayload(
            sessionId: UUID(), studentId: UUID(), status: .present,
            notes: "", clientMutationId: "m3",
            markedAt: "2026-08-24T11:00:00Z", absenceInformed: nil,
            observedMarkedAt: nil, didObserveRow: false)
        let unknownObj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(unknown)) as! [String: Any]
        XCTAssertNil(unknownObj["observed_marked_at"])
    }

    // MARK: - Student year summary

    func testStudentYearSummaryWindowStartIsOneYearEarlier() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 6))!
        let start = StudentYearSummary.windowStart(from: now, calendar: cal)
        let expected = cal.date(from: DateComponents(year: 2025, month: 8, day: 6))!
        XCTAssertEqual(start, expected)
    }

    func testStudentYearSummaryByClassAggregatesAndSorts() {
        let records = [
            historyRecord(className: "Math (Mon)", status: .present),
            historyRecord(className: "English (Thu)", status: .late),
            historyRecord(className: "Math (Mon)", status: .absent),
            historyRecord(className: "Math (Mon)", status: .present),
            historyRecord(className: "English (Thu)", status: .present),
        ]
        let summaries = StudentYearSummary.byClass(records)
        XCTAssertEqual(summaries.map(\.className), ["English (Thu)", "Math (Mon)"])
        XCTAssertEqual(summaries[0].totalSessions, 2)
        XCTAssertEqual(summaries[0].presentCount, 1)
        XCTAssertEqual(summaries[0].lateCount, 1)
        XCTAssertEqual(summaries[0].absentCount, 0)
        XCTAssertEqual(summaries[0].attendancePct, 100.0)
        XCTAssertEqual(summaries[1].totalSessions, 3)
        XCTAssertEqual(summaries[1].presentCount, 2)
        XCTAssertEqual(summaries[1].lateCount, 0)
        XCTAssertEqual(summaries[1].absentCount, 1)
        XCTAssertEqual(summaries[1].attendancePct, 66.7)
    }

    func testStudentYearSummaryEmptyInput() {
        XCTAssertTrue(StudentYearSummary.byClass([]).isEmpty)
    }

    private func historyRecord(
        className: String, status: AttendanceStatus
    ) -> AttendanceHistoryRecord {
        AttendanceHistoryRecord(
            id: UUID(),
            status: status,
            markedAt: nil,
            absenceInformed: nil,
            session: .init(
                sessionDate: "2026-07-01",
                class: .init(name: className)
            )
        )
    }

    // MARK: - Kiosk load policy
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    // MARK: - Full-screen loader

    func testFirstLoadShowsFullScreenLoader() {
        XCTAssertTrue(shouldShowFullScreenLoader(
            isLoadInFlight: true, hasEntries: false, hasLoadedSuccessfully: false))
    }

    func testSubsequentRefreshDoesNotShowFullScreenLoader() {
        XCTAssertFalse(shouldShowFullScreenLoader(
            isLoadInFlight: true, hasEntries: true, hasLoadedSuccessfully: true))
        XCTAssertFalse(shouldShowFullScreenLoader(
            isLoadInFlight: true, hasEntries: false, hasLoadedSuccessfully: true))
        XCTAssertFalse(shouldShowFullScreenLoader(
            isLoadInFlight: false, hasEntries: false, hasLoadedSuccessfully: false))
    }

    // MARK: - Auto-refresh skip

    func testAutoRefreshRunsWhenIdle() {
        XCTAssertFalse(shouldSkipKioskAutoRefresh(
            hasPendingMutations: false,
            isSelectionMode: false,
            isShowingPIN: false,
            isLoadInFlight: false
        ))
    }

    func testAutoRefreshSkipsPendingSelectionPINAndLoading() {
        XCTAssertTrue(shouldSkipKioskAutoRefresh(
            hasPendingMutations: true,
            isSelectionMode: false,
            isShowingPIN: false,
            isLoadInFlight: false
        ))
        XCTAssertTrue(shouldSkipKioskAutoRefresh(
            hasPendingMutations: false,
            isSelectionMode: true,
            isShowingPIN: false,
            isLoadInFlight: false
        ))
        XCTAssertTrue(shouldSkipKioskAutoRefresh(
            hasPendingMutations: false,
            isSelectionMode: false,
            isShowingPIN: true,
            isLoadInFlight: false
        ))
        XCTAssertTrue(shouldSkipKioskAutoRefresh(
            hasPendingMutations: false,
            isSelectionMode: false,
            isShowingPIN: false,
            isLoadInFlight: true
        ))
    }

    // MARK: - Empty-state presentation

    func testFailedEmptyLoadIsNotNoClasses() {
        XCTAssertEqual(
            kioskRosterPresentation(
                isLoadInFlight: false,
                hasEntries: false,
                hasLoadedSuccessfully: false,
                loadFailed: true
            ),
            .loadFailed
        )
    }

    func testSuccessfulEmptyLoadIsNoClasses() {
        XCTAssertEqual(
            kioskRosterPresentation(
                isLoadInFlight: false,
                hasEntries: false,
                hasLoadedSuccessfully: true,
                loadFailed: false
            ),
            .noClasses
        )
    }

    func testFailedRefreshKeepsRosterWhenEntriesExist() {
        XCTAssertEqual(
            kioskRosterPresentation(
                isLoadInFlight: false,
                hasEntries: true,
                hasLoadedSuccessfully: true,
                loadFailed: true
            ),
            .roster
        )
    }

    func testInFlightFirstLoadPresentsSpinner() {
        XCTAssertEqual(
            kioskRosterPresentation(
                isLoadInFlight: true,
                hasEntries: false,
                hasLoadedSuccessfully: false,
                loadFailed: false
            ),
            .fullScreenLoading
        )
    }

    // MARK: - Pending merge

    func testKeepLocalPendingEntryOnlyWhenIdIsPending() {
        XCTAssertTrue(shouldKeepLocalPendingEntry(studentId: a, pendingIds: [a]))
        XCTAssertFalse(shouldKeepLocalPendingEntry(studentId: a, pendingIds: [b]))
        XCTAssertFalse(shouldKeepLocalPendingEntry(studentId: a, pendingIds: []))
    }

    func testMergeKeepsPendingLocalRowAndUpdatesOthers() {
        let local = [
            entry(a, name: "Amy", status: .present),
            entry(b, name: "Ben", status: .late),
        ]
        let remote = [
            entry(a, name: "Amy", status: .absent),
            entry(b, name: "Ben", status: .present),
        ]

        let merged = mergeKioskEntriesPreservingPending(
            local: local, remote: remote, pendingIds: [a])

        XCTAssertEqual(merged.map(\.studentId), [a, b])
        XCTAssertEqual(merged[0].status, .present)
        XCTAssertEqual(merged[1].status, .present)
    }

    func testMergeWithoutPendingUsesRemoteSnapshot() {
        let local = [entry(a, name: "Amy", status: .present)]
        let remote = [entry(a, name: "Amy", status: .late), entry(b, name: "Ben", status: nil)]

        let merged = mergeKioskEntriesPreservingPending(
            local: local, remote: remote, pendingIds: [])

        XCTAssertEqual(merged.map(\.studentId), [a, b])
        XCTAssertEqual(merged[0].status, .late)
    }

    func testMergePreservesPendingLocalRowMissingFromRemote() {
        let local = [entry(a, name: "Amy", status: .present), entry(c, name: "Cam", status: .late)]
        let remote = [entry(a, name: "Amy", status: .absent)]

        let merged = mergeKioskEntriesPreservingPending(
            local: local, remote: remote, pendingIds: [c])

        XCTAssertEqual(merged.map(\.studentId), [a, c])
        XCTAssertEqual(merged[0].status, .absent)
        XCTAssertEqual(merged[1].status, .late)
    }

    // MARK: - Student-facing chrome

    func testErrorAlertIsAdminOnly() {
        XCTAssertTrue(shouldPresentKioskErrorAlert(isAdminMode: true))
        XCTAssertFalse(shouldPresentKioskErrorAlert(isAdminMode: false))
    }

    func testSearchBarIsAdminOnlyAndHiddenInSelection() {
        XCTAssertTrue(shouldShowKioskSearchBar(isAdminMode: true, isSelectionMode: false))
        XCTAssertFalse(shouldShowKioskSearchBar(isAdminMode: true, isSelectionMode: true))
        XCTAssertFalse(shouldShowKioskSearchBar(isAdminMode: false, isSelectionMode: false))
        XCTAssertFalse(shouldShowKioskSearchBar(isAdminMode: false, isSelectionMode: true))
    }

    func testKidSafeCopyDoesNotIncludeServerErrorText() {
        XCTAssertEqual(
            kioskOfflineBannerText,
            "No internet — use the paper sheet. Taps will not save."
        )
        XCTAssertFalse(kioskStudentFacingActionFailureNotice.localizedCaseInsensitiveContains("postgrest"))
        XCTAssertFalse(kioskStudentFacingActionFailureNotice.localizedCaseInsensitiveContains("error"))
        XCTAssertFalse(kioskStudentFacingRefreshFailureNotice.localizedCaseInsensitiveContains("postgrest"))
    }

    private func entry(_ id: UUID, name: String, status: AttendanceStatus?) -> KioskEntry {
        KioskEntry(
            studentId: id,
            fullName: name,
            status: status,
            sessions: [],
            markedAt: nil,
            dismissedAt: nil,
            lateReason: nil,
            absenceInformed: nil,
            avatarUrl: nil
        )
    }
}

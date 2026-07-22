import AppIntents
import XCTest
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
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markAbsent, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markNotHere, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.markDismissed, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.undoDismissal, isAdminMode: false))
        XCTAssertFalse(GlobalKioskView.isActionAuthorized(.addLateReason("traffic"), isAdminMode: false))
        XCTAssertTrue(GlobalKioskView.isActionAuthorized(.markAbsent, isAdminMode: true))
    }

    func testMalformedStoredPINRequiresAuthenticatedReset() {
        XCTAssertEqual(storedKioskPINDisposition(""), .none)
        XCTAssertEqual(storedKioskPINDisposition("1234"), .legacyPlaintext)
        XCTAssertEqual(storedKioskPINDisposition("v1:" + String(repeating: "a", count: 64)), .currentHash)
        XCTAssertEqual(storedKioskPINDisposition("v1:not-a-hash"), .requiresAuthenticatedReset)
        XCTAssertEqual(storedKioskPINDisposition("corrupt"), .requiresAuthenticatedReset)
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

    // MARK: worstStatus

    func testWorstStatusRanking() {
        XCTAssertEqual(AttendanceService.worstStatus(.late, .present), .late)
        XCTAssertEqual(AttendanceService.worstStatus(.present, .absent), .present)
        XCTAssertEqual(AttendanceService.worstStatus(.absent, .excused), .absent)
        XCTAssertEqual(AttendanceService.worstStatus(.late, .excused), .late)
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

    private func dismissal(dismissedAt: Date?, safelyHomeAt: Date?) -> Dismissal {
        Dismissal(id: UUID(), sessionId: UUID(), studentId: UUID(),
                  dismissedAt: dismissedAt, dismissedBy: nil, safelyHomeAt: safelyHomeAt)
    }

    func testAwaitingSafelyHome() {
        let confirmed = dismissal(dismissedAt: at(9, 0), safelyHomeAt: at(9, 30))
        let awaiting = dismissal(dismissedAt: at(9, 0), safelyHomeAt: nil)
        let noTimestamp = dismissal(dismissedAt: nil, safelyHomeAt: nil)
        let result = AttendanceService.awaitingSafelyHome([confirmed, awaiting, noTimestamp])
        XCTAssertEqual(result.map(\.id), [awaiting.id])
    }

    func testPushNotificationsDisabledHidesDismissals() {
        let awaiting = dismissal(dismissedAt: at(9, 0), safelyHomeAt: nil)
        XCTAssertTrue(ParentDismissalVisibility.visible(
            pushNotificationsEnabled: false,
            dismissals: [awaiting]
        ).isEmpty)
    }

    // MARK: offline queue account binding

    private func pendingRecord(ownerUserId: UUID, mutationId: String = "pending") -> PendingAttendanceRecord {
        PendingAttendanceRecord(
            ownerUserId: ownerUserId,
            sessionId: UUID(),
            studentId: UUID(),
            status: .present,
            notes: nil,
            clientMutationId: mutationId,
            markedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isSynced: false
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

    func testPendingQueueRejectsLegacyAndMixedOwnerData() {
        let owner = UUID()
        let foreign = pendingRecord(ownerUserId: UUID(), mutationId: "foreign")
        XCTAssertNil(PendingAttendanceQueueCodec.decode(Data("[]".utf8), expectedOwnerUserId: owner))
        XCTAssertNil(PendingAttendanceQueueCodec.encode(
            ownerUserId: owner,
            records: [foreign]
        ))
        XCTAssertFalse(PendingAttendanceQueueCodec.recordsBelongToOwner(
            [foreign],
            ownerUserId: owner
        ))
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
        let target = at(0, 0)
        let expected = retrospectiveSession(date: "2026-07-10")
        let sessions = [retrospectiveSession(date: "2026-07-09"), expected]
        XCTAssertEqual(RetrospectiveSessionRules.existingSession(on: target, in: sessions)?.id,
                       expected.id)
    }

    func testHistoricalEditorRequiresFlagAndPastDate() {
        let today = at(12, 0)
        XCTAssertTrue(RetrospectiveSessionRules.editorEnabled(
            for: retrospectiveSession(date: "2026-07-09"), flagEnabled: true, today: today))
        XCTAssertFalse(RetrospectiveSessionRules.editorEnabled(
            for: retrospectiveSession(date: "2026-07-10"), flagEnabled: true, today: today))
        XCTAssertFalse(RetrospectiveSessionRules.editorEnabled(
            for: retrospectiveSession(date: "2026-07-09"), flagEnabled: false, today: today))
    }
}

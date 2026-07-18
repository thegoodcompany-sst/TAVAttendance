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
                 recurrenceEndDate: nil, isStudySpace: nil)
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

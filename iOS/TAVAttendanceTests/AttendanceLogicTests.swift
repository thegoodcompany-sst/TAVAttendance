import XCTest
@testable import TAVAttendance

final class AttendanceLogicTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

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
}

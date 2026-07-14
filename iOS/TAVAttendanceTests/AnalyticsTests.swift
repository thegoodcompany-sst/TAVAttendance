import XCTest
@testable import TAVAttendance

@MainActor
final class AnalyticsTests: XCTestCase {

    // Drop-on-failure is the whole idempotency contract: analytics must NEVER
    // build a second offline queue like PendingAttendanceStore. A failed flush
    // discards the batch rather than retaining/retrying it.
    func testFlushDropsBufferedEventsWhenSinkFails() async {
        let analytics = Analytics()
        analytics.record(.ops, name: "a")
        analytics.record(.ops, name: "b")
        XCTAssertEqual(analytics.buffer.count, 2)

        await analytics.flush(using: { _ in throw AppError("offline") })

        XCTAssertTrue(analytics.buffer.isEmpty, "a failed flush must drop events, not retain them")
    }

    func testFlushForwardsBatchAndClearsBufferOnSuccess() async {
        let analytics = Analytics()
        analytics.record(.ops, name: "a")
        analytics.record(.tap, name: "b")

        var sent: [AppEvent] = []
        await analytics.flush(using: { sent = $0 })

        XCTAssertEqual(sent.map(\.name), ["a", "b"])
        XCTAssertTrue(analytics.buffer.isEmpty)
    }
}

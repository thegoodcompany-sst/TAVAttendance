import Foundation
import XCTest
@testable import PromptRouter

private final class MemoryPersistence: PendingRoutePersistence {
    enum Failure: Error { case write }
    var data: Data?
    var failWrites = false
    func load() throws -> Data? { data }
    func save(_ data: Data) throws {
        if failWrites { throw Failure.write }
        self.data = data
    }
}

final class PromptRouterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let lesson = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    private let otherLesson = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
    private let actor = UUID(uuidString: "10000000-0000-4000-8000-000000000011")!
    private let otherActor = UUID(uuidString: "10000000-0000-4000-8000-000000000012")!
    private let hosts: Set<String> = ["prompts.example.test"]
    private var link: String { "https://prompts.example.test/t/lesson/\(lesson.uuidString.lowercased())" }

    private func make(_ store: MemoryPersistence = MemoryPersistence(), at date: Date? = nil) throws -> PromptRouter {
        try PromptRouter(approvedHosts: hosts, persistence: store, now: date ?? now)
    }
    private func signedIn(_ id: UUID? = nil, role: PromptAccount.Role = .teacher,
                          active: Bool = true, unlocked: Bool = true, enabled: Bool = true) -> PromptContext {
        PromptContext(authentication: .signedIn(PromptAccount(id: id ?? actor, role: role, isActive: active)),
                      teacherPromptsEnabled: enabled, isUnlocked: unlocked)
    }
    private func request(_ router: PromptRouter, file: StaticString = #filePath, line: UInt = #line) throws -> PromptResolution {
        guard case .resolving(let result) = router.state else {
            XCTFail("Expected resolving", file: file, line: line)
            throw MemoryPersistence.Failure.write
        }
        return result
    }
    private func payload() -> [AnyHashable: Any] {
        ["v": 1, "type": "teacher_prompt", "lesson_id": lesson.uuidString.lowercased(), "kind": "attendance",
         "aps": ["alert": ["title": "TAVA", "body": "Please take attendance."], "sound": "default",
                 "category": PromptAction.category, "thread-id": "teacher-lesson:\(lesson.uuidString.lowercased())"]]
    }
    private func openSnooze(_ router: PromptRouter, responseID: String = "response-1") throws {
        XCTAssertTrue(try router.open(userInfo: payload(), actionIdentifier: "SNOOZE_10", responseID: responseID, now: now))
    }
    private func fixtures() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "routes-v1", withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testSharedURLFixtures() throws {
        let fixture = try fixtures()
        let parser = PromptParser(approvedHosts: Set(try XCTUnwrap(fixture["approved_hosts"] as? [String])))
        for row in try XCTUnwrap(fixture["urls"] as? [[String: Any]]) {
            let actual = parser.parse(link: try XCTUnwrap(row["input"] as? String))
            XCTAssertEqual(actual?.lessonID.uuidString.lowercased(), row["lesson_id"] as? String, row["name"] as? String ?? "")
        }
    }

    func testSharedPayloadFixtures() throws {
        let parser = PromptParser(approvedHosts: hosts)
        for row in try XCTUnwrap(fixtures()["payloads"] as? [[String: Any]]) {
            let actual = parser.parse(userInfo: try XCTUnwrap(row["user_info"] as? [String: Any]),
                                      actionIdentifier: try XCTUnwrap(row["action_identifier"] as? String))
            XCTAssertEqual(actual?.lessonID.uuidString.lowercased(), row["lesson_id"] as? String, row["name"] as? String ?? "")
            XCTAssertEqual(actual?.action.rawValue, row["action"] as? String, row["name"] as? String ?? "")
        }
    }

    func testURLOverload() throws {
        let parser = PromptParser(approvedHosts: hosts)
        XCTAssertEqual(parser.parse(url: try XCTUnwrap(URL(string: link)))?.lessonID, lesson)
    }

    func testNoApprovedHostsRejectsHTTPS() {
        XCTAssertNil(PromptParser(approvedHosts: []).parse(link: link))
    }

    func testInitialStateIdle() throws { XCTAssertEqual(try make().state, .idle) }

    func testSignedOutLinkSurvivesRestartAndLogin() throws {
        let store = MemoryPersistence()
        let first = try make(store)
        try first.update(context: PromptContext(authentication: .signedOut), now: now)
        XCTAssertTrue(try first.open(link: link, now: now))
        XCTAssertEqual(first.state, .awaitingSignIn)
        let restored = try make(store, at: now.addingTimeInterval(60))
        XCTAssertEqual(restored.pending?.lessonID, lesson)
        XCTAssertNil(restored.pending?.boundAccountID)
        try restored.update(context: signedIn(), now: now.addingTimeInterval(60))
        XCTAssertEqual(try request(restored).accountID, actor)
    }

    func testWaitsForProfileFlagsAndUnlock() throws {
        let router = try make()
        try router.open(link: link, now: now)
        XCTAssertEqual(router.state, .awaitingSignIn)
        try router.update(context: PromptContext(authentication: .loadingProfile(actor)), now: now)
        XCTAssertEqual(router.state, .awaitingSignIn)
        try router.update(context: signedIn(unlocked: false, enabled: false), now: now)
        XCTAssertEqual(router.state, .unavailable(.disabled))
        try router.update(context: signedIn(unlocked: false), now: now)
        XCTAssertEqual(router.state, .awaitingUnlock)
        try router.update(context: signedIn(), now: now)
        _ = try request(router)
    }

    func testParentAndInactiveTeacherDenied() throws {
        for context in [signedIn(role: .parent), signedIn(active: false), signedIn(role: .other)] {
            let router = try make()
            try router.open(link: link, now: now)
            try router.update(context: context, now: now)
            XCTAssertEqual(router.state, .unavailable(.denied))
            XCTAssertNotNil(router.pending)
        }
    }

    func testAdminStillRequiresServerResolution() throws {
        let router = try make()
        try router.update(context: signedIn(role: .admin), now: now)
        try router.open(link: link, now: now)
        let resolving = try request(router)
        try router.complete(resolving, outcome: .denied, now: now)
        XCTAssertEqual(router.state, .unavailable(.denied))
        XCTAssertNotNil(router.pending)
    }

    func testAuthorizationConsumesOnlyOnSuccess() throws {
        let store = MemoryPersistence()
        let router = try make(store)
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        XCTAssertNotNil(router.pending)
        try router.complete(request(router), outcome: .authorized, now: now)
        XCTAssertNil(router.pending)
        XCTAssertEqual(router.state, .ready(ReadyPrompt(lessonID: lesson, accountID: actor, needsSnoozeConfirmation: false)))
        XCTAssertNil(try make(store).pending)
    }

    func testNetworkFailurePreservesRouteForExplicitRetry() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        let first = try request(router)
        try router.complete(first, outcome: .networkFailure, now: now)
        XCTAssertEqual(router.state, .unavailable(.network))
        try router.refresh(now: now)
        XCTAssertEqual(router.state, .unavailable(.network))
        try router.retry(now: now)
        XCTAssertNotEqual(try request(router).id, first.id)
    }

    func testDeniedRouteSurvivesButDoesNotBindToAnotherAccount() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        try router.complete(request(router), outcome: .denied, now: now)
        try router.update(context: signedIn(otherActor), now: now)
        XCTAssertEqual(router.state, .unavailable(.accountMismatch))
        // Explicit fresh link tap is required to bind this locator to account B.
        try router.open(link: link, now: now)
        XCTAssertEqual(try request(router).accountID, otherActor)
    }

    func testExpiryAtExactly24Hours() throws {
        let router = try make()
        try router.open(link: link, now: now)
        try router.refresh(now: now.addingTimeInterval(PromptRouter.timeToLive - 1))
        XCTAssertNotNil(router.pending)
        try router.refresh(now: now.addingTimeInterval(PromptRouter.timeToLive))
        XCTAssertEqual(router.state, .unavailable(.expired))
        XCTAssertNil(router.pending)
    }

    func testExpiredRouteDiscardedOnRestart() throws {
        let store = MemoryPersistence()
        try make(store).open(link: link, now: now)
        let router = try make(store, at: now.addingTimeInterval(PromptRouter.timeToLive))
        XCTAssertNil(router.pending)
        XCTAssertEqual(router.state, .unavailable(.expired))
    }

    func testClockMovingBackwardsFailsClosed() throws {
        let router = try make()
        try router.open(link: link, now: now)
        try router.refresh(now: now.addingTimeInterval(-1))
        XCTAssertEqual(router.state, .unavailable(.expired))
    }

    func testExpiresWhileRPCIsInFlight() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        try router.complete(request(router), outcome: .authorized, now: now.addingTimeInterval(PromptRouter.timeToLive))
        XCTAssertEqual(router.state, .unavailable(.expired))
    }

    func testRepeatedNotificationResponseDeduplicatedAcrossRestart() throws {
        let store = MemoryPersistence()
        let router = try make(store)
        try openSnooze(router)
        let received = router.pending?.receivedAt
        XCTAssertFalse(try router.open(userInfo: payload(), actionIdentifier: "SNOOZE_10", responseID: "response-1", now: now.addingTimeInterval(50)))
        XCTAssertEqual(router.pending?.receivedAt, received)
        let restored = try make(store)
        XCTAssertFalse(try restored.open(userInfo: payload(), actionIdentifier: "SNOOZE_10", responseID: "response-1", now: now))
    }

    func testDuplicateAfterSuccessfulOpenDoesNotResolveAgain() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        try router.complete(request(router), outcome: .authorized, now: now)
        XCTAssertFalse(try router.open(userInfo: payload(), actionIdentifier: "SNOOZE_10", responseID: "response-1", now: now))
        XCTAssertNil(router.pending)
    }

    func testNewResponseToSameLessonResolvesAgain() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        let first = try request(router)
        try router.complete(first, outcome: .authorized, now: now)
        try openSnooze(router, responseID: "response-2")
        XCTAssertNotEqual(try request(router).id, first.id)
    }

    func testLatestLinkWinsAndOldCompletionIsIgnored() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        let old = try request(router)
        try router.open(link: "tava://teacher/lesson/\(otherLesson.uuidString.lowercased())", now: now)
        let current = try request(router)
        try router.complete(old, outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .resolving(current))
        XCTAssertEqual(router.pending?.lessonID, otherLesson)
    }

    func testInvalidInputDoesNotReplaceGoodPendingRoute() throws {
        let router = try make()
        try router.open(link: link, now: now)
        XCTAssertFalse(try router.open(link: "https://foreign.example.test/", now: now))
        XCTAssertFalse(try router.open(userInfo: payload(), actionIdentifier: "SUBMIT", responseID: "other", now: now))
        XCTAssertEqual(router.pending?.lessonID, lesson)
    }

    func testSignOutKeepsUnboundNavigation() throws {
        let router = try make()
        try router.open(link: link, now: now)
        try router.update(context: PromptContext(authentication: .signedOut), now: now)
        XCTAssertNil(router.pending?.boundAccountID)
        try router.update(context: signedIn(otherActor), now: now)
        XCTAssertEqual(try request(router).accountID, otherActor)
    }

    func testSignOutDowngradesActionAndIgnoresInFlightResponse() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        let old = try request(router)
        try router.update(context: PromptContext(authentication: .signedOut), now: now)
        try router.complete(old, outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .awaitingSignIn)
        XCTAssertEqual(router.pending?.action, .takeAttendance)
        XCTAssertEqual(router.pending?.boundAccountID, actor)
        try router.update(context: signedIn(), now: now)
        try router.complete(request(router), outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .ready(ReadyPrompt(lessonID: lesson, accountID: actor, needsSnoozeConfirmation: false)))
    }

    func testCrossAccountSnoozeRequiresFreshTap() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        try router.update(context: signedIn(otherActor), now: now)
        XCTAssertEqual(router.state, .unavailable(.accountMismatch))
        XCTAssertEqual(router.pending?.action, .takeAttendance)
        try openSnooze(router, responseID: "fresh-response")
        let next = try request(router)
        XCTAssertEqual(next.accountID, otherActor)
        try router.complete(next, outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .ready(ReadyPrompt(lessonID: lesson, accountID: otherActor, needsSnoozeConfirmation: true)))
    }

    func testSessionExpiryKeepsNavigationButDropsSnooze() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        try router.complete(request(router), outcome: .sessionExpired, now: now)
        XCTAssertEqual(router.state, .awaitingSignIn)
        XCTAssertEqual(router.pending?.action, .takeAttendance)
        try router.update(context: signedIn(), now: now)
        try router.complete(request(router), outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .ready(ReadyPrompt(lessonID: lesson, accountID: actor, needsSnoozeConfirmation: false)))
    }

    func testRestartDropsSnoozeButPreservesAccountBinding() throws {
        let store = MemoryPersistence()
        let router = try make(store)
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        let restored = try make(store)
        XCTAssertEqual(restored.pending?.action, .takeAttendance)
        XCTAssertEqual(restored.pending?.boundAccountID, actor)
        try restored.update(context: signedIn(otherActor), now: now)
        XCTAssertEqual(restored.state, .unavailable(.accountMismatch))
    }

    func testSnoozeNeverAutomaticallyMutates() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try openSnooze(router)
        try router.complete(request(router), outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .ready(ReadyPrompt(lessonID: lesson, accountID: actor, needsSnoozeConfirmation: true)))
        // No writer, network client, or mutation queue exists in this package.
    }

    func testReadyScreenClearedOnSignOutAccountChangeLockAndFlagDisable() throws {
        for changed in [PromptContext(authentication: .signedOut), signedIn(otherActor),
                        signedIn(unlocked: false), signedIn(enabled: false)] {
            let router = try make()
            try router.update(context: signedIn(), now: now)
            try router.open(link: link, now: now)
            try router.complete(request(router), outcome: .authorized, now: now)
            try router.update(context: changed, now: now)
            XCTAssertEqual(router.state, .idle)
        }
    }

    func testLockCancelsResolutionThenUnlockRechecksAuthority() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        let old = try request(router)
        try router.update(context: signedIn(unlocked: false), now: now)
        try router.complete(old, outcome: .authorized, now: now)
        XCTAssertEqual(router.state, .awaitingUnlock)
        try router.update(context: signedIn(), now: now)
        XCTAssertNotEqual(try request(router).id, old.id)
    }

    func testReopeningURLAlwaysRechecksAuthority() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        let old = try request(router)
        try router.complete(old, outcome: .authorized, now: now)
        try router.open(link: link, now: now)
        XCTAssertNotEqual(try request(router).id, old.id)
    }

    func testRepeatedContextDoesNotStartDuplicateRPC() throws {
        let router = try make()
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        let old = try request(router)
        try router.update(context: signedIn(), now: now)
        XCTAssertEqual(try request(router), old)
    }

    func testCorruptAndUnknownVersionStorageFailsClosed() throws {
        for value in ["invalid", "{\"version\":2,\"receipts\":[]}"] {
            let store = MemoryPersistence()
            store.data = Data(value.utf8)
            let router = try make(store)
            XCTAssertNil(router.pending)
            XCTAssertEqual(router.state, .unavailable(.invalidSavedRoute))
        }
    }

    func testWriteFailureCannotExposeReadyScreen() throws {
        let store = MemoryPersistence()
        let router = try make(store)
        try router.update(context: signedIn(), now: now)
        try router.open(link: link, now: now)
        let inFlight = try request(router)
        store.failWrites = true
        XCTAssertThrowsError(try router.complete(inFlight, outcome: .authorized, now: now))
        XCTAssertEqual(router.state, .unavailable(.persistence))
        XCTAssertNotNil(router.pending)
    }

    func testDiscardClearsPendingPersistently() throws {
        let store = MemoryPersistence()
        let router = try make(store)
        try router.open(link: link, now: now)
        try router.discard()
        XCTAssertEqual(router.state, .idle)
        XCTAssertNil(try make(store).pending)
    }
}

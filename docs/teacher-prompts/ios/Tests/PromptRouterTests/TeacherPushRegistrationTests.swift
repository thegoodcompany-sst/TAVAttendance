import Foundation
import XCTest
@testable import PromptRouter

@MainActor
private final class Installation: TeacherInstallationStore {
    let installationID = UUID(uuidString: "90000000-0000-4000-8000-000000000001")!
    var ownerID: UUID?
    var deviceID: UUID?
    func bindIfUnowned(to accountID: UUID) throws { if ownerID == nil { ownerID = accountID } }
    func saveDeviceID(_ id: UUID?) throws { deviceID = id }
}
@MainActor
private final class DeviceRPC: TeacherSessionRPC {
    enum Failure: Error { case network }
    let accountID = UUID(uuidString: "10000000-0000-4000-8000-000000000011")!
    var calls: [String] = []
    var parameters: [[String: String]] = []
    var failures = 0
    var holdRegistration = false
    var registration: CheckedContinuation<Void, Never>?
    func call<Parameters: Encodable, Response: Decodable>(_ name: String, parameters: Parameters,
                                                          returning: Response.Type) async throws -> Response {
        calls.append(name)
        self.parameters.append(try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(parameters)))
        if name == "register_device" {
            if holdRegistration { await withCheckedContinuation { registration = $0 } }
            return try JSONDecoder().decode(Response.self, from: Data("""
            {"device_id":"90000000-0000-4000-8000-000000000002","last_seen_at":"2027-01-07T13:00:00Z","environment":"sandbox"}
            """.utf8))
        }
        if failures > 0 { failures -= 1; throw Failure.network }
        return try JSONDecoder().decode(Response.self, from: Data("{\"revoked\":true}".utf8))
    }
}

@MainActor
final class TeacherPushRegistrationTests: XCTestCase {
    private func eligibility(_ rpc: DeviceRPC, optedIn: Bool = true, account: UUID? = nil,
                             flags: Bool = true, active: Bool = true, demo: Bool = false) -> TeacherPushEligibility {
        TeacherPushEligibility(accountID: account ?? rpc.accountID, isActiveTeacherOrAdmin: active,
                               teacherPrompts: flags, teacherPromptPush: flags, optedIn: optedIn, isDemo: demo)
    }
    private func make(_ rpc: DeviceRPC, _ store: Installation) -> TeacherPushRegistrationLifecycle {
        TeacherPushRegistrationLifecycle(service: TeacherDeviceService(rpc: rpc), installation: store,
                                         environment: .sandbox, retryDelay: { _ in })
    }
    private func register(_ lifecycle: TeacherPushRegistrationLifecycle) {
        XCTAssertTrue(lifecycle.acceptTokenCallback(for: lifecycle.generation))
        lifecycle.didRegister(token: String(repeating: "a", count: 64))
    }
    func testSharedRegistrationFixtures() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "registration-v1", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for row in try XCTUnwrap(fixture["scenarios"] as? [[String: Any]]) {
            let rpc = DeviceRPC(), store = Installation()
            rpc.failures = try XCTUnwrap(row["failures"] as? Int)
            let lifecycle = make(rpc, store)
            for event in try XCTUnwrap(row["events"] as? [String]) {
                switch event {
                case "on": lifecycle.updateEligibility(eligibility(rpc))
                case "off": lifecycle.updateEligibility(eligibility(rpc, optedIn: false))
                case "register": register(lifecycle)
                case "retry": lifecycle.retryPendingRevocation()
                case "signout": await lifecycle.beginSignOut()?.value
                default: XCTFail("Unknown fixture event")
                }
                await lifecycle.waitForIdle()
            }
            let name = row["name"] as? String ?? ""
            XCTAssertEqual(rpc.calls, row["calls"] as? [String], name)
            XCTAssertEqual(lifecycle.revocationPending, row["pending"] as? Bool, name)
            XCTAssertEqual(lifecycle.token != nil, row["has_token"] as? Bool, name)
            XCTAssertEqual(store.deviceID != nil, row["has_device"] as? Bool, name)
            for (index, call) in rpc.calls.enumerated() where call == "unregister_device" {
                XCTAssertEqual(rpc.parameters[index], ["p_installation_id": store.installationID.uuidString])
            }
        }
    }
    func testOptOutDuringRegistrationRevokesAfterCompletion() async {
        let rpc = DeviceRPC(), store = Installation(), actor = UUID()
        rpc.holdRegistration = true
        let lifecycle = make(rpc, store)
        var cleared = 0
        lifecycle.clearLocalActions = { cleared += 1 }
        lifecycle.updateEligibility(eligibility(rpc)); register(lifecycle)
        for _ in 0..<100 { if rpc.registration != nil { break }; await Task.yield() }
        XCTAssertNotNil(rpc.registration)
        lifecycle.updateEligibility(eligibility(rpc, optedIn: false))
        XCTAssertNil(lifecycle.token); XCTAssertEqual(cleared, 1)
        // A new account cannot adopt the old installation or its owner-bound RPC.
        lifecycle.updateEligibility(eligibility(rpc, account: actor))
        rpc.registration?.resume(); rpc.registration = nil
        await lifecycle.waitForIdle()
        XCTAssertEqual(rpc.calls, ["register_device", "unregister_device", "unregister_device"])
        XCTAssertEqual(store.ownerID, rpc.accountID); XCTAssertNil(store.deviceID)
        XCTAssertFalse(lifecycle.eligible)
    }
    func testReoptInRaceSerializesRevokeBeforeNewRegistration() async {
        let rpc = DeviceRPC(), store = Installation()
        rpc.holdRegistration = true
        let lifecycle = make(rpc, store)
        lifecycle.updateEligibility(eligibility(rpc)); register(lifecycle)
        for _ in 0..<100 { if rpc.registration != nil { break }; await Task.yield() }
        XCTAssertNotNil(rpc.registration)
        lifecycle.updateEligibility(eligibility(rpc, optedIn: false))
        lifecycle.updateEligibility(eligibility(rpc)); register(lifecycle)
        rpc.holdRegistration = false; rpc.registration?.resume(); rpc.registration = nil
        await lifecycle.waitForIdle()
        XCTAssertEqual(rpc.calls, ["register_device", "unregister_device", "register_device"])
        XCTAssertNotNil(store.deviceID); XCTAssertNotNil(lifecycle.token)
    }
    func testFailedRevocationKeepsRecoveryStateAndClearsToken() async {
        let rpc = DeviceRPC(), store = Installation()
        let lifecycle = make(rpc, store)
        var fallbacks: [String] = []
        lifecycle.showTodaysLessons = { fallbacks.append($0) }
        lifecycle.updateEligibility(eligibility(rpc)); register(lifecycle); await lifecycle.waitForIdle()
        rpc.failures = 10
        lifecycle.updateEligibility(eligibility(rpc, optedIn: false)); await lifecycle.waitForIdle()
        XCTAssertEqual(rpc.calls.filter { $0 == "unregister_device" }.count, 3)
        XCTAssertTrue(lifecycle.revocationPending); XCTAssertNil(lifecycle.token)
        XCTAssertEqual(fallbacks, [PromptStrings.pushUnavailable])
        lifecycle.updateEligibility(eligibility(rpc)); register(lifecycle); await lifecycle.waitForIdle()
        XCTAssertEqual(rpc.calls.filter { $0 == "register_device" }.count, 1)
        XCTAssertNil(lifecycle.token)
    }
    func testFlagsOrProfileRemovalAlsoRevokes() async {
        for flags in [true, false] {
            let rpc = DeviceRPC(), store = Installation(), lifecycle: TeacherPushRegistrationLifecycle
            lifecycle = make(rpc, store)
            lifecycle.updateEligibility(eligibility(rpc)); register(lifecycle); await lifecycle.waitForIdle()
            lifecycle.updateEligibility(eligibility(rpc, flags: flags, active: !flags))
            await lifecycle.waitForIdle()
            XCTAssertEqual(rpc.calls, ["register_device", "unregister_device"])
        }
    }
    func testStalePermissionAndTokenCallbacksAreIgnored() async {
        let rpc = DeviceRPC(), store = Installation(), lifecycle: TeacherPushRegistrationLifecycle
        lifecycle = make(rpc, store)
        lifecycle.updateEligibility(eligibility(rpc))
        let generation = lifecycle.generation
        lifecycle.updateEligibility(eligibility(rpc, optedIn: false))
        XCTAssertFalse(lifecycle.acceptTokenCallback(for: generation))
        lifecycle.didRegister(token: "fake")
        await lifecycle.waitForIdle(); XCTAssertTrue(rpc.calls.isEmpty)
    }
    func testPersistedInstallationIsRevokedEvenWithoutLocalToken() async {
        let rpc = DeviceRPC(), store = Installation()
        store.ownerID = rpc.accountID; store.deviceID = UUID()
        let lifecycle = make(rpc, store)
        lifecycle.updateEligibility(eligibility(rpc, optedIn: false)); await lifecycle.waitForIdle()
        XCTAssertEqual(rpc.calls, ["unregister_device"]); XCTAssertNil(store.deviceID)
    }
    func testForeignInstallationAndDemoCannotRegister() async {
        let rpc = DeviceRPC(), store = Installation()
        store.ownerID = UUID()
        let lifecycle = make(rpc, store)
        lifecycle.updateEligibility(eligibility(rpc))
        XCTAssertFalse(lifecycle.eligible)
        lifecycle.updateEligibility(eligibility(rpc, demo: true))
        await lifecycle.beginSignOut()?.value
        XCTAssertTrue(rpc.calls.isEmpty)
    }
}

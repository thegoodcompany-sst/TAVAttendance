// In-memory demonstration of registrar injection. No Supabase or APNs transport.
#if canImport(UIKit) && canImport(UserNotifications)
import Foundation
import PromptRouter

@MainActor
final class FakeTeacherSessionRPC: TeacherSessionRPC {
    enum Failure: Error { case unexpectedRPC }
    let accountID = UUID(uuidString: "10000000-0000-4000-8000-000000000011")!
    private(set) var registrationCount = 0
    private(set) var revocationCount = 0

    func call<Parameters: Encodable, Response: Decodable>(
        _ name: String, parameters: Parameters, returning: Response.Type
    ) async throws -> Response {
        let object: [String: Any]
        switch name {
        case "register_device":
            registrationCount += 1
            object = ["device_id": "50000000-0000-4000-8000-000000000001",
                      "last_seen_at": "2027-01-07T13:05:00Z", "environment": "sandbox"]
        case "unregister_device":
            revocationCount += 1
            object = ["revoked": true]
        default: throw Failure.unexpectedRPC
        }
        // Do not retain/log the parameters, even in a fake registrar.
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor
final class FakeTeacherInstallationStore: TeacherInstallationStore {
    enum Failure: Error { case foreignOwner }
    let installationID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
    private(set) var ownerID: UUID?
    private(set) var deviceID: UUID?
    func bindIfUnowned(to accountID: UUID) throws {
        guard ownerID == nil || ownerID == accountID else { throw Failure.foreignOwner }
        ownerID = accountID
    }
    func saveDeviceID(_ id: UUID?) throws { deviceID = id }
}

@MainActor
enum TeacherPromptDemo {
    static func makeRegistration() -> TeacherPushRegistration {
        let rpc = FakeTeacherSessionRPC()
        let registration = TeacherPushRegistration(service: TeacherDeviceService(rpc: rpc),
            installation: FakeTeacherInstallationStore(), environment: .sandbox,
            realDeviceIntegrationEnabled: false)
        registration.updateEligibility(TeacherPushEligibility(accountID: rpc.accountID,
            isActiveTeacherOrAdmin: true, teacherPrompts: true, teacherPromptPush: false,
            optedIn: false, isDemo: true))
        // requestIfEligible exits without asking permission or contacting APNs.
        return registration
    }

    static func exerciseFakeService() async throws -> RegisteredTeacherDevice {
        let rpc = FakeTeacherSessionRPC()
        return try await TeacherDeviceService(rpc: rpc).register(
            installationID: FakeTeacherInstallationStore().installationID,
            token: String(repeating: "ab", count: 32), environment: "sandbox")
    }
}
#endif

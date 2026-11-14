// Integration sketch only. Not a Package target and not linked into the app.
#if canImport(UIKit) && canImport(UserNotifications)
import Foundation
import UIKit
import UserNotifications
import PromptRouter

/// Implement in Services with a client permanently bound to this session/account.
/// Do not implement using a mutable global client whose account can switch mid-RPC.
/// Tests/demo inject an in-memory fake; this sketch does not create a Supabase client.
@MainActor
protocol TeacherSessionRPC {
    var accountID: UUID { get }
    func call<Parameters: Encodable, Response: Decodable>(
        _ name: String, parameters: Parameters, returning: Response.Type
    ) async throws -> Response
}

struct RegisteredTeacherDevice: Decodable {
    let device_id: UUID
    let last_seen_at: String
    let environment: String
}

/// Supabase interaction belongs at this service seam, never in a view or delegate.
@MainActor
final class TeacherDeviceService {
    private let rpc: any TeacherSessionRPC
    var accountID: UUID { rpc.accountID }
    init(rpc: any TeacherSessionRPC) { self.rpc = rpc }

    func register(installationID: UUID, token: String, environment: String) async throws -> RegisteredTeacherDevice {
        struct Parameters: Encodable {
            let p_installation_id: UUID
            let p_token: String
            let p_environment: String
        }
        return try await rpc.call("register_device", parameters: Parameters(
            p_installation_id: installationID, p_token: token, p_environment: environment
        ), returning: RegisteredTeacherDevice.self)
    }

    func revoke(deviceID: UUID) async throws {
        struct Parameters: Encodable { let p_device_id: UUID }
        struct Response: Decodable { let revoked: Bool }
        _ = try await rpc.call("revoke_device", parameters: Parameters(p_device_id: deviceID), returning: Response.self)
    }
}

/// Persist together atomically in the future app adapter. Neither value is an auth secret.
/// Retain the owner after logout: V2 explicitly forbids shared-installation takeover.
@MainActor
protocol TeacherInstallationStore {
    var installationID: UUID { get }
    var ownerID: UUID? { get }
    var deviceID: UUID? { get }
    func bindIfUnowned(to accountID: UUID) throws
    func saveDeviceID(_ id: UUID?) throws
}

enum TeacherAPNSEnvironment: String {
    case sandbox, production
    /// Pass the SIGNED aps-environment entitlement, never infer from DEBUG.
    init?(signedEntitlement: String) {
        switch signedEntitlement {
        case "development": self = .sandbox
        case "production": self = .production
        default: return nil
        }
    }
}

struct TeacherPushEligibility: Equatable {
    let accountID: UUID
    let isActiveTeacherOrAdmin: Bool
    let teacherPrompts: Bool
    let teacherPromptPush: Bool
    let optedIn: Bool
    let isDemo: Bool
    var allowed: Bool {
        isActiveTeacherOrAdmin && teacherPrompts && teacherPromptPush && optedIn && !isDemo
    }
}

@MainActor
final class TeacherPushRegistration {
    private let service: TeacherDeviceService
    private let installation: any TeacherInstallationStore
    private let environment: TeacherAPNSEnvironment
    // Default OFF. A later reviewed integration must explicitly allow system APNs.
    private let realDeviceIntegrationEnabled: Bool
    private var eligibility: TeacherPushEligibility?
    private var generation = UUID()
    private var awaitingToken = false
    private var deviceID: UUID?
    private var token: String? // Memory only; never print, persist, or put in a URL.
    private var registrationTask: Task<Void, Never>?
    var showTodaysLessons: (String) -> Void = { _ in }

    init(service: TeacherDeviceService, installation: any TeacherInstallationStore,
         environment: TeacherAPNSEnvironment, realDeviceIntegrationEnabled: Bool = false) {
        self.service = service
        self.installation = installation
        self.environment = environment
        self.realDeviceIntegrationEnabled = realDeviceIntegrationEnabled
        self.deviceID = installation.ownerID == service.accountID ? installation.deviceID : nil
    }

    func updateEligibility(_ value: TeacherPushEligibility?) {
        guard eligibility != value else { return }
        eligibility = value
        generation = UUID()
        awaitingToken = false
        token = nil
        // The owner-scoped service is intentionally not reused under another account.
    }

    func requestIfEligible(existingCategories: Set<UNNotificationCategory>) async {
        guard realDeviceIntegrationEnabled, eligible else { return }
        let started = generation
        do {
            let center = UNUserNotificationCenter.current()
            center.setNotificationCategories(existingCategories.union([TeacherNotificationDelegate.category]))
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard started == generation, eligible else { return }
            guard granted else { showTodaysLessons(PromptStrings.pushUnavailable); return }
            try installation.bindIfUnowned(to: service.accountID)
            guard installation.ownerID == service.accountID else {
                showTodaysLessons(PromptStrings.pushUnavailable); return
            }
            awaitingToken = true
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            showTodaysLessons(PromptStrings.pushUnavailable)
        }
    }

    /// Existing AppDelegate.didRegisterForRemoteNotifications forwards here for teachers.
    func didRegister(deviceToken: Data) {
        guard realDeviceIntegrationEnabled, awaitingToken, eligible,
              installation.ownerID == service.accountID, !deviceToken.isEmpty else { return }
        let started = generation
        let value = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = value
        let previous = registrationTask
        registrationTask = Task {
            // Serialize rotations: an older network completion must not overwrite a
            // newer token. The transport must bound each call's duration.
            await previous?.value
            guard started == generation, eligible, token == value else { return }
            do {
                let result = try await service.register(installationID: installation.installationID,
                                                        token: value, environment: environment.rawValue)
                guard started == generation, eligible, token == value else {
                    // Registration raced logout/opt-out. Use the SAME owner-scoped service.
                    if !eligible { try? await service.revoke(deviceID: result.device_id) }
                    return
                }
                deviceID = result.device_id
                try installation.saveDeviceID(result.device_id)
            } catch {
                guard started == generation, token == value else { return }
                token = nil
                showTodaysLessons(PromptStrings.pushUnavailable)
            }
        }
    }

    func didFailToRegister() {
        awaitingToken = false
        token = nil
        showTodaysLessons(PromptStrings.pushUnavailable)
    }

    /// Call synchronously before awaiting AuthManager.signOut. Await returned task BEFORE
    /// ending auth. Configure a bounded RPC timeout; failure must not prevent sign-out.
    /// Coordinator clears visible data and snooze state at the same synchronous boundary.
    func beginSignOut() -> Task<Void, Never>? {
        let registeredID = deviceID
        updateEligibility(nil)
        token = nil
        deviceID = nil
        do { try installation.saveDeviceID(nil) }
        catch { showTodaysLessons(PromptStrings.storageUnavailable) }
        let inFlight = registrationTask
        registrationTask = nil
        guard registeredID != nil || inFlight != nil else { return nil }
        return Task {
            await inFlight?.value
            if let registeredID { try? await service.revoke(deviceID: registeredID) }
        }
    }

    private var eligible: Bool {
        guard let eligibility else { return false }
        return eligibility.allowed && eligibility.accountID == service.accountID
            && (installation.ownerID == nil || installation.ownerID == service.accountID)
    }
}
#endif

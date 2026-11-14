import Foundation

/// Implement using an immutable account-bound client with a bounded request timeout.
/// Never switch the client's account while a registration/revocation is outstanding.
@MainActor
public protocol TeacherSessionRPC {
    var accountID: UUID { get }
    func call<Parameters: Encodable, Response: Decodable>(
        _ name: String, parameters: Parameters, returning: Response.Type
    ) async throws -> Response
}

public struct RegisteredTeacherDevice: Decodable {
    public let device_id: UUID
    public let last_seen_at: String
    public let environment: String
}

@MainActor
public final class TeacherDeviceService {
    private let rpc: any TeacherSessionRPC
    public let accountID: UUID
    public init(rpc: any TeacherSessionRPC) { self.rpc = rpc; self.accountID = rpc.accountID }
    public func register(installationID: UUID, token: String, environment: String) async throws -> RegisteredTeacherDevice {
        struct Parameters: Encodable {
            let p_installation_id: UUID
            let p_token: String
            let p_environment: String
        }
        return try await rpc.call("register_device", parameters: Parameters(
            p_installation_id: installationID, p_token: token, p_environment: environment
        ), returning: RegisteredTeacherDevice.self)
    }
    public func unregister(installationID: UUID) async throws {
        struct Parameters: Encodable { let p_installation_id: UUID }
        struct Response: Decodable { let revoked: Bool }
        let result = try await rpc.call("unregister_device", parameters: Parameters(
            p_installation_id: installationID
        ), returning: Response.self)
        guard result.revoked else { throw TeacherDeviceFailure.revocation }
    }
}
private enum TeacherDeviceFailure: Error { case revocation }

/// Persist atomically. Retain owner after logout; installations cannot change owners.
@MainActor
public protocol TeacherInstallationStore {
    var installationID: UUID { get }
    var ownerID: UUID? { get }
    var deviceID: UUID? { get }
    func bindIfUnowned(to accountID: UUID) throws
    func saveDeviceID(_ id: UUID?) throws
}

public enum TeacherAPNSEnvironment: String {
    case sandbox, production
    public init?(signedEntitlement: String) {
        switch signedEntitlement {
        case "development": self = .sandbox
        case "production": self = .production
        default: return nil
        }
    }
}

public struct TeacherPushEligibility: Equatable {
    public let accountID: UUID
    public let isActiveTeacherOrAdmin: Bool
    public let teacherPrompts: Bool
    public let teacherPromptPush: Bool
    public let optedIn: Bool
    public let isDemo: Bool
    public init(accountID: UUID, isActiveTeacherOrAdmin: Bool, teacherPrompts: Bool,
                teacherPromptPush: Bool, optedIn: Bool, isDemo: Bool) {
        self.accountID = accountID; self.isActiveTeacherOrAdmin = isActiveTeacherOrAdmin
        self.teacherPrompts = teacherPrompts; self.teacherPromptPush = teacherPromptPush
        self.optedIn = optedIn; self.isDemo = isDemo
    }
    public var allowed: Bool {
        isActiveTeacherOrAdmin && teacherPrompts && teacherPromptPush && optedIn && !isDemo
    }
}

/// Foundation-only lifecycle. Tests inject fake RPCs and never call APNs.
@MainActor
public final class TeacherPushRegistrationLifecycle {
    private let service: TeacherDeviceService
    private let installation: any TeacherInstallationStore
    private let environment: TeacherAPNSEnvironment
    private let retryDelay: (Int) async -> Void
    private var eligibility: TeacherPushEligibility?
    public private(set) var generation = UUID()
    private var awaitingToken = false
    private(set) var token: String? // Memory only; not logged, persisted or put in URLs.
    private var tail: Task<Void, Never>?
    public private(set) var revocationPending = false
    public var showTodaysLessons: (String) -> Void = { _ in }
    // The coordinator clears actor-bound actions at this same synchronous boundary.
    public var clearLocalActions: () -> Void = {}

    public init(service: TeacherDeviceService, installation: any TeacherInstallationStore,
                environment: TeacherAPNSEnvironment,
                retryDelay: @escaping (Int) async -> Void = { attempt in
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }) {
        self.service = service; self.installation = installation
        self.environment = environment; self.retryDelay = retryDelay
    }
    public var eligible: Bool {
        guard let eligibility else { return false }
        return eligibility.allowed && eligibility.accountID == service.accountID
            && (installation.ownerID == nil || installation.ownerID == service.accountID)
    }
    public func updateEligibility(_ value: TeacherPushEligibility?) {
        guard eligibility != value else { return }
        let wasEligible = eligible
        eligibility = value; generation = UUID(); awaitingToken = false; token = nil
        if !eligible {
            clearLocalActions()
            if wasEligible || installation.ownerID == service.accountID { enqueueRevocation() }
        }
    }
    /// Called after OS permission, with the generation captured before that await.
    public func acceptTokenCallback(for requestGeneration: UUID) -> Bool {
        guard requestGeneration == generation, eligible else { return false }
        do {
            try installation.bindIfUnowned(to: service.accountID)
            guard installation.ownerID == service.accountID else { return false }
            awaitingToken = true
            return true
        } catch { showTodaysLessons(PromptStrings.pushUnavailable); return false }
    }
    public func didRegister(token value: String) {
        guard awaitingToken, eligible, installation.ownerID == service.accountID, !value.isEmpty else { return }
        let started = generation
        token = value
        let previous = tail
        tail = Task {
            await previous?.value
            guard started == generation, eligible, token == value else { return }
            // A failed earlier opt-out must finish before re-registering.
            if revocationPending {
                await revokeWithRetry()
                guard !revocationPending else { token = nil; return }
            }
            guard started == generation, eligible, token == value else { return }
            do {
                let result = try await service.register(installationID: installation.installationID,
                                                        token: value, environment: environment.rawValue)
                // Any opt-out queued while the RPC was in flight runs after this task.
                guard started == generation, eligible, token == value else { return }
                try installation.saveDeviceID(result.device_id)
            } catch {
                guard started == generation else { return }
                token = nil; showTodaysLessons(PromptStrings.pushUnavailable)
            }
        }
    }
    public func didFailToRegister() {
        awaitingToken = false; token = nil
        showTodaysLessons(PromptStrings.pushUnavailable)
    }
    private func enqueueRevocation() {
        guard installation.ownerID == service.accountID else { return }
        revocationPending = true
        let previous = tail
        tail = Task {
            // This revocation must still run if the user opts back in meanwhile.
            // A later registration queues behind it, so it cannot revoke the new token.
            await previous?.value
            await revokeWithRetry()
        }
    }
    private func revokeWithRetry() async {
        for attempt in 1...3 {
            do {
                try await service.unregister(installationID: installation.installationID)
                try installation.saveDeviceID(nil)
                revocationPending = false
                return
            } catch {
                if attempt < 3 { await retryDelay(attempt) }
            }
        }
        revocationPending = true
        showTodaysLessons(PromptStrings.pushUnavailable)
    }
    /// Explicit foreground/network recovery retries once more, with the same three-call bound.
    public func retryPendingRevocation() {
        if revocationPending { enqueueRevocation() }
    }
    /// Await BEFORE ending this owner's session. RPC transport must enforce its timeout.
    /// Exhausted retries surface fallback but never prevent sign-out indefinitely.
    public func beginSignOut() -> Task<Void, Never>? {
        if eligibility == nil { token = nil; awaitingToken = false; clearLocalActions(); enqueueRevocation() }
        else { updateEligibility(nil) }
        return tail
    }
    public func waitForIdle() async { await tail?.value }
}

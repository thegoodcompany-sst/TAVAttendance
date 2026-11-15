import Foundation
import UIKit
import UserNotifications
import Security
import PromptRouter

/// Small Keychain documents, device-only; no token, roster or feedback is persisted.
final class TeacherPromptKeychain: PendingRoutePersistence {
    private let key: String
    init(_ key: String) { self.key = key }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "TAVA") + ".teacher-prompts",
         kSecAttrAccount as String: key]
    }
    func load() throws -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TeacherPromptError.unavailable }
        return data
    }
    func save(_ data: Data) throws {
        let attrs: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TeacherPromptError.unavailable }
    }
}

@MainActor
final class TeacherPromptInstallation: TeacherInstallationStore {
    private struct Snapshot: Codable {
        var installationID: UUID
        var ownerID: UUID?
        var deviceID: UUID?
    }
    private let storage: any PendingRoutePersistence
    private var snapshot: Snapshot
    var installationID: UUID { snapshot.installationID }
    var ownerID: UUID? { snapshot.ownerID }
    var deviceID: UUID? { snapshot.deviceID }
    init(storage: any PendingRoutePersistence) throws {
        self.storage = storage
        if let data = try storage.load() { snapshot = try JSONDecoder().decode(Snapshot.self, from: data) }
        else {
            snapshot = Snapshot(installationID: UUID())
            try storage.save(JSONEncoder().encode(snapshot))
        }
    }
    func bindIfUnowned(to accountID: UUID) throws {
        guard ownerID == nil || ownerID == accountID else { throw TeacherPromptError.unavailable }
        var next = snapshot; next.ownerID = accountID
        try storage.save(JSONEncoder().encode(next)); snapshot = next
    }
    func saveDeviceID(_ id: UUID?) throws {
        var next = snapshot; next.deviceID = id
        try storage.save(JSONEncoder().encode(next)); snapshot = next
    }
}

@MainActor
protocol TeacherPromptNotificationEffects {
    func removeDelivered(lessonID: UUID) async
    func badge(_ count: Int) async
}
@MainActor
final class TeacherPromptSystemNotifications: TeacherPromptNotificationEffects {
    func removeDelivered(lessonID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let id = lessonID.uuidString.lowercased()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            $0.request.content.categoryIdentifier == PromptAction.category &&
            ($0.request.content.threadIdentifier == "teacher-lesson:\(id)" ||
             $0.request.content.userInfo["lesson_id"] as? String == id)
        }.map { $0.request.identifier })
    }
    func badge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }
}
@MainActor
final class TeacherPromptDemoNotifications: TeacherPromptNotificationEffects {
    func removeDelivered(lessonID: UUID) async {}
    func badge(_ count: Int) async {}
}

/// OS adapter for the package's tested, serialized registration lifecycle.
@MainActor
final class TeacherPushRegistration {
    let lifecycle: TeacherPushRegistrationLifecycle
    private let environmentConfigured: Bool
    private var requestedGeneration: UUID?
    init(rpc: any TeacherSessionRPC, installation: any TeacherInstallationStore,
         environment: TeacherAPNSEnvironment?) {
        environmentConfigured = environment != nil
        lifecycle = TeacherPushRegistrationLifecycle(service: TeacherDeviceService(rpc: rpc),
            installation: installation, environment: environment ?? .sandbox)
    }
    func requestIfEligible() async {
        guard TeacherPromptsGate.masterEnabled, lifecycle.eligible, !DemoMode.isActive else { return }
        guard environmentConfigured else { lifecycle.didFailToRegister(); return }
        let generation = lifecycle.generation
        guard requestedGeneration != generation else { return }
        requestedGeneration = generation
        let center = UNUserNotificationCenter.current()
        let categories = await center.notificationCategories()
        guard generation == lifecycle.generation, lifecycle.eligible else { return }
        center.setNotificationCategories(categories.union([TeacherNotificationDelegate.category]))
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard generation == lifecycle.generation, lifecycle.eligible else { return }
            guard granted else { requestedGeneration = nil; lifecycle.didFailToRegister(); return }
            guard lifecycle.acceptTokenCallback(for: generation) else { return }
            PushManager.teacherTokenRequested = true
            UIApplication.shared.registerForRemoteNotifications()
        } catch { requestedGeneration = nil; lifecycle.didFailToRegister() }
    }
    func didRegister(_ data: Data) {
        guard TeacherPromptsGate.masterEnabled, !DemoMode.isActive else { return }
        lifecycle.didRegister(token: data.map { String(format: "%02x", $0) }.joined())
    }
}

/// Retained by AppDelegate (UNUserNotificationCenter.delegate itself is weak).
final class TeacherNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: PromptAction.category, actions: [
            UNNotificationAction(identifier: PromptAction.takeAttendance.rawValue, title: PromptStrings.takeAttendance,
                                 options: [.foreground, .authenticationRequired]),
            UNNotificationAction(identifier: PromptAction.snoozeTen.rawValue, title: PromptStrings.snoozeTen,
                                 options: [.foreground, .authenticationRequired])
        ], intentIdentifiers: [], options: [])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() }
            let request = response.notification.request
            TeacherPromptCoordinator.shared.open(userInfo: request.content.userInfo,
                action: response.actionIdentifier, responseID: request.identifier)
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let coordinator = TeacherPromptCoordinator.shared
            let show = coordinator.shouldPresent(userInfo: notification.request.content.userInfo)
            completionHandler(show ? [.banner, .list] : [])
            if show { await coordinator.foreground() }
        }
    }
}

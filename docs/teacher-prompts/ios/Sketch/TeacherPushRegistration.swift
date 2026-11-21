// Integration sketch only. Not linked into the app. Lifecycle is tested in the package.
#if canImport(UIKit) && canImport(UserNotifications)
import Foundation
import UIKit
import UserNotifications
import PromptRouter

@MainActor
final class TeacherPushRegistration {
    let lifecycle: TeacherPushRegistrationLifecycle
    // Default OFF; tests never request APNs permission or registration.
    private let realDeviceIntegrationEnabled: Bool
    var showTodaysLessons: (String) -> Void {
        get { lifecycle.showTodaysLessons }
        set { lifecycle.showTodaysLessons = newValue }
    }
    var clearLocalActions: () -> Void {
        get { lifecycle.clearLocalActions }
        set { lifecycle.clearLocalActions = newValue }
    }
    init(service: TeacherDeviceService, installation: any TeacherInstallationStore,
         environment: TeacherAPNSEnvironment, realDeviceIntegrationEnabled: Bool = false) {
        lifecycle = TeacherPushRegistrationLifecycle(service: service, installation: installation, environment: environment)
        self.realDeviceIntegrationEnabled = realDeviceIntegrationEnabled
    }
    func updateEligibility(_ value: TeacherPushEligibility?) { lifecycle.updateEligibility(value) }
    func requestIfEligible(existingCategories: Set<UNNotificationCategory>) async {
        guard realDeviceIntegrationEnabled, lifecycle.eligible else { return }
        let started = lifecycle.generation
        do {
            let center = UNUserNotificationCenter.current()
            center.setNotificationCategories(existingCategories.union([TeacherNotificationDelegate.category]))
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard started == lifecycle.generation, lifecycle.eligible else { return }
            guard granted else { lifecycle.didFailToRegister(); return }
            guard lifecycle.acceptTokenCallback(for: started) else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch { lifecycle.didFailToRegister() }
    }
    func didRegister(deviceToken: Data) {
        guard realDeviceIntegrationEnabled else { return }
        lifecycle.didRegister(token: deviceToken.map { String(format: "%02x", $0) }.joined())
    }
    func didFailToRegister() { lifecycle.didFailToRegister() }
    func beginSignOut() -> Task<Void, Never>? { lifecycle.beginSignOut() }
    func retryPendingRevocation() { lifecycle.retryPendingRevocation() }
}
#endif

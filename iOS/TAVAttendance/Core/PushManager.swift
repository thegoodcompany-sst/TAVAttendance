import SwiftUI
import UIKit
import UserNotifications

/// PROD-02 — registers for APNs and stores the device token so the notify-parent
/// edge function can reach parents. Entirely gated by the `push_notifications`
/// feature flag; does nothing until the flag is on (and real APNs entitlements +
/// keys are configured — see HUMANS.md).
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var teacherDelegate: TeacherNotificationDelegate?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if TeacherPromptsGate.masterEnabled {
            let delegate = TeacherNotificationDelegate()
            teacherDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
        }
        return true
    }
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            let prompts = TeacherPromptCoordinator.shared
            switch TeacherPromptsGate.tokenPath(master: TeacherPromptsGate.masterEnabled,
                role: TeacherPromptsGate.masterEnabled ? prompts.currentRole : PushManager.currentRole, teacherRequest: PushManager.teacherTokenRequested) {
            case .teacher:
                prompts.registration?.didRegister(deviceToken)
            case .ignored:
                break
            case .parent:
                guard !DemoMode.isActive else { return }
                let token = deviceToken.map { String(format: "%02x", $0) }.joined()
                try? await AttendanceService.shared.registerDeviceToken(token, platform: "ios")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("PushManager: registration failed (\(type(of: error)))")
        #endif
        Task { @MainActor in
            TeacherPromptCoordinator.shared.registration?.lifecycle.didFailToRegister()
        }
    }
}

@MainActor
enum PushManager {
    static var currentRole: String?
    static var teacherTokenRequested = false
    /// Requests notification authorization and registers for remote notifications,
    /// but only when the push_notifications flag is enabled.
    static func registerIfEnabled() async {
        if TeacherPromptsGate.masterEnabled {
            let prompts = TeacherPromptCoordinator.shared
            if prompts.currentRole == "teacher" || prompts.currentRole == "admin" {
                await prompts.requestRegistration()
                return
            }
            // Never use a previous account's cached parent role during profile loading.
            guard prompts.currentRole == "parent" else { return }
        }
        guard currentRole != "teacher" else { return }
        guard !DemoMode.isActive, FeatureFlagStore.shared.isEnabled(.pushNotifications) else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        teacherTokenRequested = false
        UIApplication.shared.registerForRemoteNotifications()
    }
}

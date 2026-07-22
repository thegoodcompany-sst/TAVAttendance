import SwiftUI
import UIKit
import UserNotifications

/// PROD-02 — registers for APNs and stores the device token so the notify-parent
/// edge function can reach parents. Entirely gated by the `push_notifications`
/// feature flag; does nothing until the flag is on (and real APNs entitlements +
/// keys are configured — see HUMANS.md).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await AttendanceService.shared.registerDeviceToken(token, platform: "ios") }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("PushManager: registration failed (\(type(of: error)))")
        #endif
    }
}

@MainActor
enum PushManager {
    /// Requests notification authorization and registers for remote notifications,
    /// but only when the push_notifications flag is enabled.
    static func registerIfEnabled() async {
        guard FeatureFlagStore.shared.isEnabled(.pushNotifications) else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

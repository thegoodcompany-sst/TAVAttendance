import SwiftUI

/// The selectable tabs in the admin tab bar. Backed by `Int` so it can drive
/// a `TabView(selection:)` binding directly.
enum AppTab: Int {
    case classes = 0
    case students = 1
    case signIn = 2
}

/// Lightweight, app-wide router used by App Intents (Siri) to switch the admin
/// tab bar to a given tab when the app is opened by an intent.
///
/// `OpenKioskIntent` sets `selectedTab` on the main actor; `AdminTabView` binds
/// its `TabView(selection:)` to this value so the change takes effect immediately.
@MainActor
final class KioskRouter: ObservableObject {
    static let shared = KioskRouter()
    @Published var selectedTab: AppTab = .classes
    private init() {}
}

/// Process-local kiosk authorization shared with App Intents. A configured PIN
/// never authorizes Siri/Shortcuts until it has been entered in this app launch.
@MainActor
final class KioskSecurityState: ObservableObject {
    static let shared = KioskSecurityState()
    @Published var isAdminUnlocked = false

    var allowsAppIntents: Bool {
        Self.allowsAppIntents(
            hasConfiguredPIN: !(UserDefaults.standard.string(forKey: "kioskPIN") ?? "").isEmpty,
            isAdminUnlocked: isAdminUnlocked
        )
    }

    static func allowsAppIntents(hasConfiguredPIN: Bool, isAdminUnlocked: Bool) -> Bool {
        !hasConfiguredPIN || isAdminUnlocked
    }

    nonisolated static func allowsSensitiveEntityQueries(isAdminUnlocked: Bool) -> Bool {
        isAdminUnlocked
    }

    /// Revokes kiosk admin authorization app-wide when the app backgrounds, even if the
    /// kiosk tab is not currently mounted. App Intents share this process-local state.
    func relockIfConfigured() {
        let hasConfiguredPIN = !(UserDefaults.standard.string(forKey: "kioskPIN") ?? "").isEmpty
        guard hasConfiguredPIN else { return }
        isAdminUnlocked = false
        UserDefaults.standard.set(true, forKey: "kioskLocked")
    }

    private init() {}
}

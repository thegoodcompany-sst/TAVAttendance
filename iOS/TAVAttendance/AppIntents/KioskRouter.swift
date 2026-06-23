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

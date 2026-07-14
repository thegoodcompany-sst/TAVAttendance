import SwiftUI

@main
struct TAVAttendanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var featureFlags = FeatureFlagStore.shared

    var body: some Scene {
        WindowGroup {
            if authManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authManager.isAuthenticated {
                Group {
                    switch authManager.currentProfile?.role {
                    case "admin":
                        AdminTabView()
                    case "parent":
                        ParentDashboardView()
                    default:
                        TutorTabView()
                    }
                }
                .environmentObject(authManager)
                .environmentObject(featureFlags)
                .task {
                    // PROD-02: register for push once flags are loaded (no-op while off).
                    await PushManager.registerIfEnabled()
                    // Analytics: start timer/observers + emit app_launch (no-op unless flag on).
                    Analytics.shared.start()
                }
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
    }
}

private struct TutorTabView: View {
    var body: some View {
        TabView {
            ClassListView()
                .tabItem { Label("Classes", systemImage: "rectangle.3.group") }
            StudentResultsView()
                .tabItem { Label("Students", systemImage: "person.3") }
        }
    }
}

private struct AdminTabView: View {
    // Bound to the App Intents router so "Open the sign-in kiosk" (Siri) can switch tabs.
    @ObservedObject private var router = KioskRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ClassListView()
                .tabItem { Label("Classes", systemImage: "rectangle.3.group") }
                .tag(AppTab.classes)
            StudentManagementView()
                .tabItem { Label("Students", systemImage: "person.3") }
                .tag(AppTab.students)
            GlobalKioskView()
                .tabItem { Label("Sign-In", systemImage: "person.wave.2") }
                .tag(AppTab.signIn)
        }
    }
}

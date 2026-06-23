import SwiftUI

@main
struct TAVAttendanceApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authManager.isAuthenticated {
                if authManager.currentProfile?.role == "admin" {
                    AdminTabView()
                        .environmentObject(authManager)
                } else {
                    ClassListView()
                        .environmentObject(authManager)
                }
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
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

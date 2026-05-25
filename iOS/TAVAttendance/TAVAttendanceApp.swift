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
    var body: some View {
        TabView {
            ClassListView()
                .tabItem { Label("Classes", systemImage: "rectangle.3.group") }
            StudentManagementView()
                .tabItem { Label("Students", systemImage: "person.3") }
            GlobalKioskView()
                .tabItem { Label("Sign-In", systemImage: "person.wave.2") }
        }
    }
}

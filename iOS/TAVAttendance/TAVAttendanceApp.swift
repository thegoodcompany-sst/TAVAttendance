import SwiftUI

@main
struct TAVAttendanceApp: App {
    @StateObject private var auth    = AuthManager.shared
    @StateObject private var network = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.profile == nil {
                    LoginView()
                } else {
                    // Route to appropriate view based on role
                    if auth.selectedRole == .tutor {
                        AttendanceTakerView()
                    } else {
                        ClassListView()
                    }
                }
            }
            .environmentObject(auth)
            .environmentObject(network)
        }
    }
}

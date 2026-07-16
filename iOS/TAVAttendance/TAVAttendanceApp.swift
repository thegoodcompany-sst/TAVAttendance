import SwiftUI

@main
struct TAVAttendanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var featureFlags = FeatureFlagStore.shared
    @AppStorage("biometricUnlockEnabled") private var biometricUnlockEnabled = false
    @State private var isBioUnlocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if authManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authManager.isAuthenticated {
                ZStack {
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
                    if biometricUnlockEnabled && !isBioUnlocked {
                        BiometricLockView(isUnlocked: $isBioUnlocked)
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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { isBioUnlocked = false }
                }
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
    }
}

private struct BiometricLockView: View {
    @Binding var isUnlocked: Bool
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("TAVA Attendance")
                .font(.title2.bold())
            Button {
                Task { await attempt() }
            } label: {
                Label("Unlock with \(Biometrics.biometryName() ?? "Passcode")",
                      systemImage: "faceid")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
            Button("Sign Out", role: .destructive) {
                Task { try? await authManager.signOut() }
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await attempt() }
    }

    private func attempt() async {
        isUnlocked = await Biometrics.authenticate(reason: "Unlock TAVA Attendance")
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

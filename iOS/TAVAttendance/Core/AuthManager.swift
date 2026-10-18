import SwiftUI
import Supabase

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentProfile: Profile? = nil
    @Published var isLoading = true
    /// Changes whenever demo data is (re)seeded so the signed-in UI rebuilds and reloads.
    @Published private(set) var demoDataGeneration = UUID()

    private let supabase = SupabaseManager.shared.client

    init() {
        // A relaunch inside demo mode stays in demo mode (with freshly seeded data).
        if DemoMode.wasActiveOnLastLaunch {
            enterDemoMode()
        }
        Task {
            await listenToAuthChanges()
        }
    }

    // MARK: - On-device demo mode

    /// Switches to the seeded on-device demo. No Supabase call is made.
    func enterDemoMode() {
        PendingAttendanceStore.shared.clear()
        DemoMode.setActive(true)
        DemoStore.shared.reset()
        FeatureFlagStore.shared.applyDemoFlags()
        Analytics.shared.role = DemoMode.profile.role
        currentProfile = DemoMode.profile
        demoDataGeneration = UUID()
        isAuthenticated = true
        isLoading = false
    }

    /// Throws away every change made during the demo and reseeds it.
    func resetDemoData() {
        guard DemoMode.isActive else { return }
        DemoStore.shared.reset()
        demoDataGeneration = UUID()
    }

    private func exitDemoMode() {
        DemoMode.setActive(false)
        DemoStore.shared.reset()
        FeatureFlagStore.shared.clear()
        PendingAttendanceStore.shared.clear()
        Analytics.shared.role = nil
        currentProfile = nil
        isAuthenticated = false
        isLoading = false
    }

    private func listenToAuthChanges() async {
        if !DemoMode.isActive { isLoading = true }
        for await (event, session) in supabase.auth.authStateChanges {
            // Demo mode owns the signed-in state; ignore Supabase session events.
            if DemoMode.isActive {
                isLoading = false
                continue
            }
            switch event {
            case .signedIn:
                if let userId = session?.user.id {
                    PendingAttendanceStore.shared.activateOwner(userId)
                    isAuthenticated = true
                    await fetchProfile(userId: userId)
                } else {
                    PendingAttendanceStore.shared.clear()
                    isAuthenticated = false
                }
                isLoading = false
            case .signedOut:
                PendingAttendanceStore.shared.clear()
                isAuthenticated = false
                currentProfile = nil
                isLoading = false
            case .initialSession:
                if let userId = session?.user.id {
                    PendingAttendanceStore.shared.activateOwner(userId)
                    isAuthenticated = true
                    await fetchProfile(userId: userId)
                } else {
                    PendingAttendanceStore.shared.clear()
                    isAuthenticated = false
                }
                isLoading = false
            default:
                break
            }
        }
    }

    private func fetchProfile(userId: UUID) async {
        guard !DemoMode.isActive else { return }
        // Role drives which UI is shown (admin/parent/tutor). A nil profile silently
        // falls through to the tutor UI — an admin/parent would land in the wrong app.
        // Retry a few times, then sign out rather than route them incorrectly.
        for attempt in 1...3 {
            do {
                let profile: Profile = try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value
                currentProfile = profile
                Analytics.shared.role = profile.role
                // Refresh feature flags once we have an authenticated session.
                await FeatureFlagStore.shared.load()
                return
            } catch {
                #if DEBUG
                print("AuthManager: profile fetch failed (attempt \(attempt)/3, \(type(of: error)))")
                #endif
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }
        // Couldn't resolve the role — sign out so the user isn't dropped into the
        // wrong-role UI. They land back on the login screen and can retry.
        try? await signOut()
    }

    func signIn(email: String, password: String) async throws {
        if DemoMode.isDemoEmail(email) {
            enterDemoMode()
            return
        }
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        if DemoMode.isActive {
            exitDemoMode()
            return
        }
        // Clear synchronously before the auth request so no stale queue survives an
        // offline/failed sign-out or becomes visible to a subsequent account.
        PendingAttendanceStore.shared.clear()
        try await supabase.auth.signOut()
    }
}

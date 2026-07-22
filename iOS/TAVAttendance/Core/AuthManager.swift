import SwiftUI
import Supabase

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentProfile: Profile? = nil
    @Published var isLoading = true

    private let supabase = SupabaseManager.shared.client

    init() {
        Task {
            await listenToAuthChanges()
        }
    }

    private func listenToAuthChanges() async {
        isLoading = true
        for await (event, session) in supabase.auth.authStateChanges {
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
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        // Clear synchronously before the auth request so no stale queue survives an
        // offline/failed sign-out or becomes visible to a subsequent account.
        PendingAttendanceStore.shared.clear()
        try await supabase.auth.signOut()
    }
}

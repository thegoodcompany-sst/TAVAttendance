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
                isAuthenticated = true
                if let userId = session?.user.id {
                    await fetchProfile(userId: userId)
                }
                isLoading = false
            case .signedOut:
                isAuthenticated = false
                currentProfile = nil
                isLoading = false
            case .initialSession:
                if let userId = session?.user.id {
                    isAuthenticated = true
                    await fetchProfile(userId: userId)
                } else {
                    isAuthenticated = false
                }
                isLoading = false
            default:
                break
            }
        }
    }

    private func fetchProfile(userId: UUID) async {
        do {
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            currentProfile = profile
        } catch {
            print("AuthManager: failed to fetch profile — \(error)")
        }
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }
}

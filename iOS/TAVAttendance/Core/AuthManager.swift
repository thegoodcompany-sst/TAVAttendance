import Supabase
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var profile: Profile?
    @Published var isLoading = true

    private let db = SupabaseManager.shared.client

    private init() {
        Task { await listenForAuthChanges() }
    }

    // MARK: - Auth State

    private func listenForAuthChanges() async {
        isLoading = true
        for await state in db.auth.authStateChanges {
            switch state.event {
            case .initialSession, .signedIn:
                if state.session != nil {
                    await fetchProfile()
                } else {
                    profile = nil
                    isLoading = false
                }
            case .signedOut, .userDeleted:
                profile = nil
                isLoading = false
            default:
                break
            }
        }
    }

    private func fetchProfile() async {
        guard let userId = db.auth.currentUser?.id else {
            isLoading = false
            return
        }
        do {
            profile = try await db
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            print("AuthManager: failed to fetch profile — \(error)")
        }
        isLoading = false
    }

    // MARK: - Actions

    func signIn(email: String, password: String) async throws {
        try await db.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await db.auth.signOut()
    }
}

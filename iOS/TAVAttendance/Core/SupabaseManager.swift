import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectURL)!,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}

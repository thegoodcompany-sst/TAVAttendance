import Supabase
import Foundation

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Secrets.supabaseURL)!,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }
}

// MARK: - Secrets
// Replace these values after running `supabase start` (local dev)
// or from Supabase Dashboard → Settings → API (production).
private enum Secrets {
    // Local dev (from `supabase start` output):
    static let supabaseURL     = "http://127.0.0.1:54321"
    static let supabaseAnonKey = "REPLACE_WITH_ANON_KEY_FROM_SUPABASE_START"

    // Production: swap the two lines above for:
    // static let supabaseURL     = "https://YOUR_PROJECT_REF.supabase.co"
    // static let supabaseAnonKey = "YOUR_PROD_ANON_KEY"
}

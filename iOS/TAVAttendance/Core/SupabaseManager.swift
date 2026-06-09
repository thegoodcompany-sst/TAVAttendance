import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            fatalError("Supabase config missing. Add SUPABASE_PROJECT_URL and SUPABASE_ANON_KEY to Config.xcconfig (copy from Config.xcconfig.example).")
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
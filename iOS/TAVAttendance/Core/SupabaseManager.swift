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
    static let supabaseURL     = "https://zgikcbsxzjgbigywxbbj.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnaWtjYnN4empnYmlneXd4YmJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwODc4MjcsImV4cCI6MjA5NDY2MzgyN30.Qc6aN2qsA9G1GxXUDduXlDXp08qADPcvB_W1ucD0dE0"
}

import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://zgikcbsxzjgbigywxbbj.supabase.co")!,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnaWtjYnN4empnYmlneXd4YmJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwODc4MjcsImV4cCI6MjA5NDY2MzgyN30.Qc6aN2qsA9G1GxXUDduXlDXp08qADPcvB_W1ucD0dE0"
        )
    }
}

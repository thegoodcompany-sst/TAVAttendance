import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        // A missing or malformed Config.xcconfig must not crash the app: the
        // on-device demo needs no server, and a real sign-in then fails with a
        // visible connection error instead of a launch crash.
        let configuredURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_URL") as? String)
            .flatMap { URL(string: $0) }
            .flatMap { url -> URL? in url.scheme?.hasPrefix("http") == true && url.host != nil ? url : nil }
        let configuredKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
            .flatMap { key -> String? in key.isEmpty || key.hasPrefix("$(") ? nil : key }
        #if DEBUG
        if configuredURL == nil || configuredKey == nil {
            print("SupabaseManager: Supabase config missing. Add SUPABASE_PROJECT_URL and SUPABASE_ANON_KEY to Config.xcconfig (copy from Config.xcconfig.example).")
        }
        #endif
        let url = configuredURL ?? URL(string: "https://config-missing.invalid")!
        let anonKey = configuredKey ?? "config-missing"
        // Every request goes through DemoNetworkGuard first, which refuses to send
        // anything while on-device demo mode is active.
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(global: .init(session: DemoNetworkGuard.guardedSession()))
        )
    }
}
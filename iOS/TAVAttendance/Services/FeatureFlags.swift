import SwiftUI
import Supabase

/// Feature flags backed by the `feature_flags` Postgres table (migration 012).
/// Flags ship OFF; an admin flips them when a feature is ready. Read once after
/// sign-in and exposed app-wide via `@EnvironmentObject`.
enum FeatureFlag: String {
    case parentPortal       = "parent_portal"
    case pushNotifications  = "push_notifications"
    case studentPhotos      = "student_photos"
    case studySpaceTracking = "study_space_tracking"
    case testMode           = "test_mode"
    case sessionNotes       = "session_notes"
    case qrSignIn           = "qr_sign_in"
}

@MainActor
final class FeatureFlagStore: ObservableObject {
    static let shared = FeatureFlagStore()

    @Published private(set) var flags: [String: Bool] = [:]

    private let db = SupabaseManager.shared.client

    private struct Row: Decodable { let key: String; let enabled: Bool }

    /// Refreshes the flag cache. Safe to call repeatedly (e.g. after sign-in).
    func load() async {
        do {
            let rows: [Row] = try await db
                .from("feature_flags")
                .select("key, enabled")
                .execute()
                .value
            flags = Dictionary(rows.map { ($0.key, $0.enabled) }, uniquingKeysWith: { _, last in last })
        } catch {
            // Fail closed: an unreachable flag table leaves every feature OFF.
            print("FeatureFlagStore: failed to load flags — \(error)")
        }
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        flags[flag.rawValue] ?? false
    }
}

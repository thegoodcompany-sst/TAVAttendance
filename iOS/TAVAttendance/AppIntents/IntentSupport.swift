import Foundation
import AppIntents
import Supabase

/// Errors surfaced to Siri / the Shortcuts app. Each maps to a spoken sentence so
/// the user hears a friendly explanation instead of a crash or a generic failure.
enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case notAdmin
    case kioskLocked
    case studentNotInToday(String)
    case noClassesToday

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            return "Please open TAVAttendance and sign in as an admin first."
        case .notAdmin:
            return "This action is only available to admin accounts. Sign in to the kiosk as an admin."
        case .kioskLocked:
            return "Open TAVAttendance, configure a kiosk PIN if needed, and unlock it before using Siri or Shortcuts."
        case .studentNotInToday(let name):
            return "\(name) doesn't have a class today, so there's nothing to sign in."
        case .noClassesToday:
            return "There are no classes scheduled today."
        }
    }
}

/// Shared helpers for the App Intents layer. Intents run inside the app process and
/// reuse the same authenticated Supabase client as the UI, so the persisted session
/// is available even when launched cold by Siri.
enum IntentSupport {

    /// Verifies there is an authenticated admin session and returns the admin profile.
    /// Throws a spoken `AppIntentError` when signed out or not an admin — the kiosk
    /// requires an admin account (see CLAUDE.md).
    @discardableResult
    static func requireAdminSession() async throws -> Profile {
        try await requireKioskAuthorization()
        let client = SupabaseManager.shared.client

        // `auth.session` throws when there is no stored/refreshable session.
        // Note: the user id is read here to avoid naming the Supabase `Session`
        // type, which would clash with this app's own `Session` model.
        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            throw AppIntentError.notSignedIn
        }

        let profile: Profile
        do {
            profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            throw AppIntentError.notSignedIn
        }

        guard profile.role == "admin" else { throw AppIntentError.notAdmin }
        return profile
    }

    /// Confirms there is an authenticated session (any role) for read-only intents.
    static func requireSession() async throws {
        try await requireKioskAuthorization()
        do {
            _ = try await SupabaseManager.shared.client.auth.session
        } catch {
            throw AppIntentError.notSignedIn
        }
    }

    /// Entity queries can run while the system is configuring or resolving an intent, before
    /// `perform()` is called. Do not rely on the enclosing intent's authentication policy to
    /// protect student/class names: require a PIN-authenticated unlock in this app process.
    /// A no-PIN kiosk therefore fails closed for entity discovery until a PIN is configured
    /// and explicitly entered.
    static func requireSensitiveEntityQueryAuthorization() async throws {
        let explicitlyUnlocked = await MainActor.run {
            KioskSecurityState.shared.isAdminUnlocked
        }
        guard KioskSecurityState.allowsSensitiveEntityQueries(
            isAdminUnlocked: explicitlyUnlocked
        ) else { throw AppIntentError.kioskLocked }
        try await requireSession()
    }

    /// The Supabase session persists across launches, while the kiosk PIN unlock
    /// intentionally does not. Enforce both boundaries for every App Intent path.
    static func requireKioskAuthorization() async throws {
        let allowed = await MainActor.run { KioskSecurityState.shared.allowsAppIntents }
        guard allowed else { throw AppIntentError.kioskLocked }
    }

    /// Finds today's kiosk entry for a student id, or nil if the student has no class today.
    static func findEntry(for studentId: UUID, in entries: [KioskEntry]) -> KioskEntry? {
        entries.first { $0.studentId == studentId }
    }
}

/// Human-readable label for an attendance status, used in spoken dialog.
extension AttendanceStatus {
    var spokenLabel: String {
        switch self {
        case .present: return "On Time"
        case .late:    return "Late"
        case .absent:  return "Absent"
        case .excused: return "Not Here"
        }
    }
}

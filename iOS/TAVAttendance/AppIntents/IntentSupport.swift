import Foundation
import AppIntents
import Supabase

/// Errors surfaced to Siri / the Shortcuts app. Each maps to a spoken sentence so
/// the user hears a friendly explanation instead of a crash or a generic failure.
enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case notAdmin
    case studentNotInToday(String)
    case noClassesToday

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            return "Please open TAVAttendance and sign in as an admin first."
        case .notAdmin:
            return "This action is only available to admin accounts. Sign in to the kiosk as an admin."
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
        do {
            _ = try await SupabaseManager.shared.client.auth.session
        } catch {
            throw AppIntentError.notSignedIn
        }
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

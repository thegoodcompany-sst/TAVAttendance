import Foundation
import Supabase

final class AttendanceService {
    static let shared = AttendanceService()
    /// Module-internal Supabase client for domain extensions. Views must not access this directly.
    let db = SupabaseManager.shared.client

    /// "yyyy-MM-dd" formatter pinned to a POSIX Gregorian calendar. A device set to a
    /// non-Gregorian calendar (e.g. Buddhist/Japanese) would otherwise format session
    /// dates in that calendar's era/year, splitting kiosk vs tutor sessions for the
    /// same real day. Used for session_date reads/writes.
    static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private init() {}
}

import Foundation
import Supabase

final class AttendanceService {
    static let shared = AttendanceService()
    /// Module-internal Supabase client for domain extensions. Views must not access this directly.
    let db = SupabaseManager.shared.client

    /// Centre civil time. Session dates, weekday scheduling, and the late
    /// threshold are Asia/Singapore, not the device time zone.
    static let singaporeTimeZone = TimeZone(identifier: "Asia/Singapore")!

    static let singaporeCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = singaporeTimeZone
        return calendar
    }()

    /// "yyyy-MM-dd" formatter pinned to a POSIX Gregorian calendar in
    /// Asia/Singapore. A device set to a non-Gregorian calendar (e.g.
    /// Buddhist/Japanese) would otherwise format session dates in that
    /// calendar's era/year, splitting kiosk vs tutor sessions for the same
    /// real day. An unpinned time zone would also split Sunday 23:00 UTC from
    /// Monday 07:00 Singapore. Used for session_date reads/writes.
    static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = singaporeCalendar
        f.timeZone = singaporeTimeZone
        return f
    }()

    private init() {}
}

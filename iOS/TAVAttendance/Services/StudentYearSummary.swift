import Foundation

struct ClassYearSummary: Identifiable, Equatable {
    let className: String
    let totalSessions: Int
    let presentCount: Int
    let lateCount: Int
    let absentCount: Int

    var id: String { className }

    /// nil when totalSessions == 0. Matches the `attendance_summary` formula:
    /// (present + late) / total, rounded to 1 decimal place.
    var attendancePct: Double? {
        guard totalSessions > 0 else { return nil }
        let raw = 100.0 * Double(presentCount + lateCount) / Double(totalSessions)
        return (raw * 10).rounded() / 10
    }
}

enum StudentYearSummary {
    /// Rolling 12 months back from `now`.
    static func windowStart(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: -1, to: now) ?? now
    }

    /// Groups history by class name, sorted by class name ascending (matches web's
    /// `.order('class_name')`).
    static func byClass(_ records: [AttendanceHistoryRecord]) -> [ClassYearSummary] {
        var buckets: [String: (present: Int, late: Int, absent: Int, total: Int)] = [:]
        for record in records {
            let name = record.session.`class`.name
            var bucket = buckets[name] ?? (0, 0, 0, 0)
            bucket.total += 1
            switch record.status {
            case .present: bucket.present += 1
            case .late:    bucket.late += 1
            case .absent:  bucket.absent += 1
            }
            buckets[name] = bucket
        }
        return buckets.keys.sorted().map { name in
            let b = buckets[name]!
            return ClassYearSummary(
                className: name,
                totalSessions: b.total,
                presentCount: b.present,
                lateCount: b.late,
                absentCount: b.absent
            )
        }
    }
}

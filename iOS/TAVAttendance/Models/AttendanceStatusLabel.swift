import Foundation

/// Shared attendance status labels used by kiosk, roster, session detail, and
/// the Students tab year-detail screen. Absent is one status with an optional
/// companion flag — never a fourth enum case.
enum AttendanceStatusLabel {
    static func text(for status: AttendanceStatus?, absenceInformed: Bool? = nil) -> String {
        switch status {
        case .present: return "On Time"
        case .late:    return "Late"
        case .absent:
            switch absenceInformed {
            case .some(true):  return "Absent (informed)"
            case .some(false): return "Absent (no notice)"
            case .none:        return "Absent"
            }
        case nil: return "Not Here Yet"
        }
    }

    /// Roster / session-detail wording uses "Present" instead of "On Time".
    static func rosterText(for status: AttendanceStatus?, absenceInformed: Bool? = nil) -> String {
        switch status {
        case .present: return "Present"
        case .late:    return "Late"
        case .absent:
            switch absenceInformed {
            case .some(true):  return "Absent (informed)"
            case .some(false): return "Absent (no notice)"
            case .none:        return "Absent"
            }
        case nil: return "Not Here Yet"
        }
    }
}

import Foundation
import AppIntents

/// App Intents-facing enum for attendance status. Mirrors `AttendanceStatus` but uses
/// the kiosk's user-facing labels ("On Time", "Not Here") so spoken phrases feel natural.
enum AttendanceStatusAppEnum: String, AppEnum {
    case present
    case late
    case absent
    case excused

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Attendance Status"

    static var caseDisplayRepresentations: [AttendanceStatusAppEnum: DisplayRepresentation] = [
        .present: "On Time",
        .late:    "Late",
        .absent:  "Absent",
        .excused: "Not Here",
    ]

    /// Bridge to the domain model used by `AttendanceService`.
    var status: AttendanceStatus {
        switch self {
        case .present: return .present
        case .late:    return .late
        case .absent:  return .absent
        case .excused: return .excused
        }
    }
}

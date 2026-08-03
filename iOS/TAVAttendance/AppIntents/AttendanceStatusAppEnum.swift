import Foundation
import AppIntents

/// App Intents-facing choices, including clearing a mark back to Not Here Yet.
enum AttendanceStatusAppEnum: String, AppEnum {
    case present
    case late
    case absent
    case notHereYet

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Attendance Status"

    static var caseDisplayRepresentations: [AttendanceStatusAppEnum: DisplayRepresentation] = [
        .present: "On Time",
        .late:    "Late",
        .absent:  "Absent",
        .notHereYet: "Not Here Yet",
    ]

    /// Bridge to the domain model used by `AttendanceService`.
    var status: AttendanceStatus? {
        switch self {
        case .present: return .present
        case .late:    return .late
        case .absent:  return .absent
        case .notHereYet: return nil
        }
    }
}

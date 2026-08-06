import Foundation
import AppIntents

/// "Mark Wayne Tan absent" / "...late" / "...present" / "...not here yet" — updates
/// attendance status across all of today's sessions for the student. Marking Absent asks
/// for confirmation first, since it cannot be undone by the student.
struct MarkAttendanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Attendance"
    static var description = IntentDescription(
        "Marks a student as On Time, Late, Absent, or Not Here Yet for today's class.")

    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Student")
    var student: StudentEntity

    @Parameter(title: "Status")
    var status: AttendanceStatusAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$student) as \(\.$status)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.requireAdminSession()

        let entries = try await AttendanceService.shared.fetchKioskEntries()
        guard let entry = IntentSupport.findEntry(for: student.id, in: entries) else {
            throw AppIntentError.studentNotInToday(student.name)
        }

        // Absent is a hard, student-irreversible mark — confirm before applying.
        // Siri cannot ask "informed?"; leave absence_informed nil intentionally.
        if status == .absent {
            try await requestConfirmation(
                result: .result(dialog: "Mark \(student.name) absent for today?"))
        }

        if let attendanceStatus = status.status {
            try await AttendanceService.shared.markKioskAttendance(
                entry: entry, status: attendanceStatus, absenceInformed: nil)
            return .result(dialog: "Marked \(student.name) as \(attendanceStatus.spokenLabel).")
        }
        try await AttendanceService.shared.clearKioskAttendance(entry: entry)
        return .result(dialog: "Marked \(student.name) as Not Here Yet.")
    }
}

import Foundation
import AppIntents

/// "Is Wayne Tan here today?" — reports a student's current attendance status for today.
struct CheckStudentStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Student Status"
    static var description = IntentDescription(
        "Tells you whether a student has signed in today and their current status.")

    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check if \(\.$student) is here today")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.requireSession()

        let entries = try await AttendanceService.shared.fetchKioskEntries()
        guard let entry = IntentSupport.findEntry(for: student.id, in: entries) else {
            return .result(dialog: "\(student.name) doesn't have a class today.")
        }

        guard let status = entry.status else {
            return .result(dialog: "\(student.name) hasn't signed in yet today.")
        }

        let dialog: IntentDialog
        switch status {
        case .present:
            dialog = "Yes — \(student.name) signed in On Time."
        case .late:
            dialog = "\(student.name) is here, but signed in Late."
        case .absent:
            dialog = "\(student.name) is marked Absent today."
        case .excused:
            dialog = "\(student.name) is marked Not Here today."
        }
        return .result(dialog: dialog)
    }
}

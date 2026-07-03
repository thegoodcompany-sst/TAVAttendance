import Foundation
import AppIntents

/// "Sign in Wayne Tan" — marks a student in across all of today's sessions, applying the
/// same auto-late logic as a kiosk tap (On Time before class start, Late after).
struct SignInStudentIntent: AppIntent {
    static var title: LocalizedStringResource = "Sign In Student"
    static var description = IntentDescription(
        "Signs a student in for today's class, marking them On Time or Late automatically.")

    // The marking happens in the background; no need to foreground the app.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Sign in \(\.$student)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.requireAdminSession()

        let entries = try await AttendanceService.shared.fetchKioskEntries()
        guard let entry = IntentSupport.findEntry(for: student.id, in: entries) else {
            throw AppIntentError.studentNotInToday(student.name)
        }

        try await AttendanceService.shared.markKioskSignIn(entry: entry)

        // Re-read to report the resulting status (On Time vs Late).
        let refreshed = try await AttendanceService.shared.fetchKioskEntries()
        let status = IntentSupport.findEntry(for: student.id, in: refreshed)?.status
        let label = status?.spokenLabel ?? "signed in"

        return .result(dialog: "Signed in \(student.name) — marked \(label).")
    }
}

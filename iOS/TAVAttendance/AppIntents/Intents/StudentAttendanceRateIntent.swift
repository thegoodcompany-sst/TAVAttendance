import Foundation
import AppIntents

/// "What's Wayne Tan's attendance rate?" — computes the attendance rate over a recent
/// window (default 30 days), matching the Student Profile screen's definition:
/// rate = (present + late) / total.
struct StudentAttendanceRateIntent: AppIntent {
    static var title: LocalizedStringResource = "Student Attendance Rate"
    static var description = IntentDescription(
        "Reports a student's recent attendance rate and a breakdown by status.")

    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Student")
    var student: StudentEntity

    @Parameter(title: "Days", default: 30)
    var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Attendance rate for \(\.$student) over the last \(\.$days) days")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.requireSession()

        let window = max(1, days)
        let since = Calendar.current.date(byAdding: .day, value: -window, to: Date())
        let history = try await AttendanceService.shared.fetchStudentAttendanceHistory(
            studentId: student.id, since: since)

        guard !history.isEmpty else {
            return .result(dialog: "\(student.name) has no attendance records in the last \(window) days.")
        }

        let present = history.filter { $0.status == .present }.count
        let late = history.filter { $0.status == .late }.count
        let absent = history.filter { $0.status == .absent }.count
        let total = history.count
        let rate = Int((Double(present + late) / Double(total) * 100).rounded())

        return .result(dialog: "\(student.name)'s attendance is \(rate) percent over the last \(window) days: \(present) on time, \(late) late, \(absent) absent.")
    }
}

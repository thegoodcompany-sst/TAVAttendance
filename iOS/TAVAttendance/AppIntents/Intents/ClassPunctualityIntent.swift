import Foundation
import AppIntents

/// "How punctual is P5 Math?" — reports a class's on-time / late / absent breakdown over
/// the last 30 days, using the same `class_punctuality` RPC as the session list screen.
struct ClassPunctualityIntent: AppIntent {
    static var title: LocalizedStringResource = "Class Punctuality"
    static var description = IntentDescription(
        "Reports a class's on-time, late, and absent rates over the last 30 days.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Class")
    var targetClass: ClassEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Punctuality for \(\.$targetClass)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.requireSession()

        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -30, to: to) ?? to
        let summary = try await AttendanceService.shared.fetchClassPunctuality(
            classId: targetClass.id, from: from, to: to)

        guard summary.totalCount > 0 else {
            return .result(dialog: "\(targetClass.name) has no attendance records in the last 30 days.")
        }

        let total = Double(summary.totalCount)
        let onTime = Int((Double(summary.presentCount) / total * 100).rounded())
        let late = Int((Double(summary.lateCount) / total * 100).rounded())
        let absent = Int((Double(summary.absentCount) / total * 100).rounded())

        return .result(dialog: "Over the last 30 days, \(targetClass.name) is \(onTime) percent on time, \(late) percent late, and \(absent) percent absent.")
    }
}

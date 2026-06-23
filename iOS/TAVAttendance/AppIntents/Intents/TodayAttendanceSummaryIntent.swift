import Foundation
import AppIntents

/// "How many students have signed in today?" — reports the attended/total count, either
/// across all of today's classes, or for one specific class if named.
struct TodayAttendanceSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Attendance Summary"
    static var description = IntentDescription(
        "Reports how many students have signed in today, overall or for a specific class.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Class (optional)")
    var targetClass: ClassEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("How many students have signed in for \(\.$targetClass)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.requireSession()

        // Class-specific: read that class's roster directly (kiosk entries don't carry
        // the class id, so we resolve today's session for the class instead).
        if let targetClass {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())

            let session = try await AttendanceService.shared.getOrCreateSession(
                classId: targetClass.id, date: today)
            let roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
            let attended = roster.filter { $0.status == .present || $0.status == .late }.count
            return .result(dialog: "\(attended) of \(roster.count) students have signed in for \(targetClass.name) today.")
        }

        // Global: aggregate across all of today's classes.
        let entries = try await AttendanceService.shared.fetchKioskEntries()
        guard !entries.isEmpty else {
            return .result(dialog: "There are no classes scheduled today.")
        }
        let attended = entries.filter { $0.isAttending }.count
        return .result(dialog: "\(attended) of \(entries.count) students have signed in today.")
    }
}

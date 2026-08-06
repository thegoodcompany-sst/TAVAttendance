import SwiftUI

/// Students-tab year detail sheet. Mirrors the web student page layout
/// (by-class summary + recent register) over a rolling 12-month window.
/// Separate from `StudentProfileView` (30-day roster/parent sheet).
struct StudentDetailView: View {
    let student: Student

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    @State private var history: [AttendanceHistoryRecord] = []
    @State private var isLoading = true
    @State private var historyError: AppError?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    private let isoParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var classSummaries: [ClassYearSummary] {
        StudentYearSummary.byClass(history)
    }

    private var recentRegister: [AttendanceHistoryRecord] {
        Array(history.prefix(50))
    }

    private var isAdmin: Bool {
        authManager.currentProfile?.role == "admin"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = historyError, history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(err.message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        headerSection

                        Section {
                            if classSummaries.isEmpty {
                                ContentUnavailableView(
                                    "No Records (Last 12 Months)",
                                    systemImage: "calendar.badge.exclamationmark",
                                    description: Text("No sessions recorded for this student in the past year.")
                                )
                            } else {
                                ForEach(classSummaries) { summary in
                                    classSummaryRow(summary)
                                }
                            }
                        } header: {
                            Text("Attendance by class (last 12 months)")
                        } footer: {
                            if !isAdmin {
                                Text("Showing only the classes you teach.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !recentRegister.isEmpty {
                            Section("Recent register") {
                                ForEach(recentRegister) { record in
                                    historyRow(record)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(student.fullName)
            .navigationBarTitleDisplayMode(.large)
            .analyticsScreen("student_detail")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .errorAlertWithRetry(error: $historyError) {
                Task { await load() }
            }
            .task { await load() }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(student.fullName)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    if let school = student.school {
                        Text(school)
                    }
                    if student.school != nil, student.yearOfStudy != nil {
                        Text("·")
                    }
                    if let year = student.yearOfStudy {
                        Text(year)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func classSummaryRow(_ summary: ClassYearSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.className)
                    .font(.subheadline.weight(.semibold))
                Text("\(summary.totalSessions) sessions · \(summary.presentCount) present · \(summary.lateCount) late · \(summary.absentCount) absent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(pctLabel(summary.attendancePct))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(pctColor(summary.attendancePct))
        }
        .padding(.vertical, 2)
    }

    private func historyRow(_ record: AttendanceHistoryRecord) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color(for: record.status))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.session.`class`.name)
                    .font(.subheadline.weight(.semibold))
                Text(formattedDate(record.session.sessionDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(AttendanceStatusLabel.rosterText(
                    for: record.status, absenceInformed: record.absenceInformed))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color(for: record.status))
                if let t = record.markedAt {
                    Text(timeFormatter.string(from: t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        isLoading = true
        historyError = nil
        do {
            // ~104 tuition sessions/year at Mon+Thu; 1000 leaves headroom for
            // multi-class students and test_mode days without a second page.
            history = try await AttendanceService.shared.fetchStudentAttendanceHistory(
                studentId: student.id,
                limit: 1000,
                since: StudentYearSummary.windowStart(from: Date())
            )
        } catch {
            historyError = AppError(
                String(localized: "Couldn't load attendance. Check your connection and try again."),
                underlyingError: error
            )
        }
        isLoading = false
    }

    private func formattedDate(_ iso: String) -> String {
        guard let d = isoParser.date(from: iso) else { return iso }
        return dateFormatter.string(from: d)
    }

    private func color(for status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .late:    return .orange
        case .absent:  return .red
        }
    }

    /// Web `PctBadge` thresholds: ≥80 emerald, ≥60 amber, else rose.
    private func pctColor(_ pct: Double?) -> Color {
        guard let pct else { return .secondary }
        if pct >= 80 { return .green }
        if pct >= 60 { return .orange }
        return .red
    }

    private func pctLabel(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        if pct == pct.rounded() {
            return "\(Int(pct))%"
        }
        return String(format: "%.1f%%", pct)
    }
}

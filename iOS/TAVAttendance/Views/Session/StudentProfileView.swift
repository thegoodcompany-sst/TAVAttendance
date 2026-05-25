import SwiftUI

struct StudentProfileView: View {
    let studentId: UUID
    let fullName: String

    @State private var history: [AttendanceHistoryRecord] = []
    @State private var isLoading = true
    @State private var loadError: String?

    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadHistory() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if history.isEmpty {
                    ContentUnavailableView(
                        "No Attendance Records",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No sessions have been recorded for this student yet.")
                    )
                } else {
                    List(history) { record in
                        historyRow(record)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(fullName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadHistory() }
    }

    private func historyRow(_ record: AttendanceHistoryRecord) -> some View {
        HStack(spacing: 12) {
            // Status indicator dot
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
                Text(record.status.rawValue.capitalized)
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

    private func loadHistory() async {
        isLoading = true
        loadError = nil
        do {
            history = try await AttendanceService.shared.fetchStudentAttendanceHistory(studentId: studentId)
        } catch {
            loadError = error.localizedDescription
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
        case .excused: return .gray
        }
    }
}

import SwiftUI

struct SessionDetailView: View {
    let session: Session
    let tavClass: TAVClass

    @State private var roster: [RosterEntry] = []
    @State private var isLoading = true
    @State private var selectedStudent: RosterEntry? = nil
    @State private var error: AppError? = nil

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private let prettyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    // MARK: - Computed stats

    private var presentCount: Int { roster.filter { $0.status == .present }.count }
    private var lateCount: Int    { roster.filter { $0.status == .late }.count }
    private var absentCount: Int  { roster.filter { $0.status == .absent }.count }
    private var excusedCount: Int { roster.filter { $0.status == .excused }.count }
    private var unmarkedCount: Int { roster.filter { $0.status == nil }.count }
    private var totalCount: Int   { roster.count }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading session…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if roster.isEmpty {
                ContentUnavailableView(
                    "No Records",
                    systemImage: "person.3",
                    description: Text("No students were enrolled or marked for this session.")
                )
            } else {
                List {
                    summarySection
                    studentSection
                }
                .listStyle(.insetGrouped)
                .sheet(item: $selectedStudent) { entry in
                    StudentProfileView(studentId: entry.studentId, fullName: entry.fullName)
                }
            }
        }
        .navigationTitle(formattedDate(session.sessionDate))
        .navigationBarTitleDisplayMode(.large)
        .task { await loadRoster() }
        .errorAlert(error: $error)
    }

    // MARK: - Summary section

    private var summarySection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    statPill("Present", count: presentCount, color: .green)
                    statPill("Late",    count: lateCount,    color: .orange)
                    statPill("Absent",  count: absentCount,  color: .red)
                    if excusedCount > 0 {
                        statPill("Excused", count: excusedCount, color: .gray)
                    }
                }
                .frame(maxWidth: .infinity)

                if let startedAt = session.startedAt {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Started \(timeFormatter.string(from: startedAt))")
                            .foregroundStyle(.secondary)
                        if let endedAt = session.endedAt {
                            Text("· Ended \(timeFormatter.string(from: endedAt))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Summary · \(totalCount) students")
        }
    }

    // MARK: - Student section

    private var studentSection: some View {
        Section("Attendance") {
            ForEach(sortedRoster) { entry in
                Button {
                    selectedStudent = entry
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.fullName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if let markedAt = entry.markedAt {
                                Text("Marked \(timeFormatter.string(from: markedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        statusBadge(for: entry.status)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var sortedRoster: [RosterEntry] {
        roster.sorted {
            statusSortOrder($0.status) < statusSortOrder($1.status)
        }
    }

    private func statusSortOrder(_ status: AttendanceStatus?) -> Int {
        switch status {
        case .present: return 0
        case .late:    return 1
        case .absent:  return 2
        case .excused: return 3
        case nil:      return 4
        }
    }

    private func statPill(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusBadge(for status: AttendanceStatus?) -> some View {
        let (label, color) = statusDisplay(status)
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func statusDisplay(_ status: AttendanceStatus?) -> (String, Color) {
        switch status {
        case .present: return ("Present", .green)
        case .late:    return ("Late",    .orange)
        case .absent:  return ("Absent",  .red)
        case .excused: return ("Excused", .gray)
        case nil:      return ("—",       .secondary)
        }
    }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = displayFormatter.date(from: isoDate) else { return isoDate }
        return prettyFormatter.string(from: date)
    }

    private func loadRoster() async {
        isLoading = true
        defer { isLoading = false }
        do {
            roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
        } catch {
            self.error = AppError("Failed to load roster", underlyingError: error)
        }
    }
}

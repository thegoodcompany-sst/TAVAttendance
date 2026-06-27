import SwiftUI

/// Internal Study Space (drop-in room) attendance — migration 015.
///
/// Present / Not Here only (no late/absent). Roster is ALL active students.
/// This attendance is internal reference ONLY and is EXCLUDED from every report,
/// report card, and parent view (see CLAUDE.md "Study Space tracking" invariant).
/// Gated by the `study_space_tracking` feature flag; reached from the kiosk header.
struct StudySpaceView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session: Session?
    @State private var roster: [RosterEntry] = []
    @State private var isLoading = true
    @State private var pendingIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var error: AppError? = nil

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)]

    private var filteredRoster: [RosterEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return roster }
        return roster.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
    }

    private var presentCount: Int { roster.filter { $0.status == .present }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading…").controlSize(.large)
                } else if roster.isEmpty {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.3",
                        description: Text("No active students to track in the Study Space.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredRoster) { entry in
                                StudySpaceCard(
                                    entry: entry,
                                    isPending: pendingIds.contains(entry.studentId)
                                ) {
                                    Task { await toggle(entry) }
                                }
                            }
                        }
                        .padding(24)
                    }
                    .searchable(text: $searchText, prompt: "Search students")
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Study Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !roster.isEmpty {
                        Text("\(presentCount) / \(roster.count) present")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .errorAlert(error: $error)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await AttendanceService.shared.loadStudySpace()
            session = result.session
            roster = result.roster
        } catch {
            self.error = AppError("Couldn't load the Study Space roster.", underlyingError: error)
        }
    }

    /// Toggles a student between Present and Not Here (excused). Unmarked → Present.
    private func toggle(_ entry: RosterEntry) async {
        guard let session else { return }
        let newStatus: AttendanceStatus = (entry.status == .present) ? .excused : .present
        pendingIds.insert(entry.studentId)
        defer { pendingIds.remove(entry.studentId) }
        do {
            try await AttendanceService.shared.markAttendance(
                sessionId: session.id, studentId: entry.studentId, status: newStatus)
            if let idx = roster.firstIndex(where: { $0.studentId == entry.studentId }) {
                roster[idx].status = newStatus
            }
        } catch {
            self.error = AppError("Couldn't update attendance. Check your connection and try again.",
                                  underlyingError: error)
        }
    }
}

private struct StudySpaceCard: View {
    let entry: RosterEntry
    let isPending: Bool
    let onTap: () -> Void

    private var isPresent: Bool { entry.status == .present }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: isPresent ? "checkmark.circle.fill" : "person.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(isPresent ? Color.green : Color.secondary)
                Text(entry.fullName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                Text(isPresent ? "Present" : "Not Here")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPresent ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(.vertical, 12)
            .background(isPresent ? Color.green.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                if isPending { ProgressView().padding(8) }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPending)
    }
}

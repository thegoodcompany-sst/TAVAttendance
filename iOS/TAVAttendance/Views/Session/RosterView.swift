import SwiftUI

struct RosterView: View {
    let session: TAVSession
    let className: String

    @StateObject private var viewModel: RosterViewModel
    @EnvironmentObject private var network: NetworkMonitor

    init(session: TAVSession, className: String) {
        self.session   = session
        self.className = className
        _viewModel = StateObject(wrappedValue: RosterViewModel(session: session))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading roster…")
            } else if viewModel.roster.isEmpty {
                ContentUnavailableView(
                    "No Students",
                    systemImage: "person.3",
                    description: Text("No students are enrolled in this class.")
                )
            } else {
                List(viewModel.roster) { entry in
                    RosterRowView(
                        entry: entry,
                        isOffline: !network.isConnected
                    ) { newStatus in
                        viewModel.mark(studentId: entry.studentId, status: newStatus)
                    }
                }
            }
        }
        .navigationTitle(className)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(className).font(.headline)
                    Text(session.sessionDate).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !network.isConnected {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Label("Offline", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: network.isConnected) { _, connected in
            if connected { Task { await viewModel.syncPending() } }
        }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Roster Row

struct RosterRowView: View {
    let entry: RosterEntry
    let isOffline: Bool
    let onMark: (AttendanceStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.fullName).font(.headline)
                Spacer()
                if isOffline {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            HStack(spacing: 8) {
                ForEach(AttendanceStatus.allCases) { status in
                    Button(status.shortLabel) {
                        onMark(status)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint(for: status))
                    .fontWeight(entry.status == status ? .bold : .regular)
                    .overlay {
                        if entry.status == status {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(tint(for: status) ?? .primary, lineWidth: 2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tint(for status: AttendanceStatus) -> Color? {
        switch status {
        case .present: return .green
        case .absent:  return .red
        case .late:    return .orange
        case .excused: return .blue
        }
    }
}

// MARK: - ViewModel

@MainActor
final class RosterViewModel: ObservableObject {
    @Published var roster: [RosterEntry] = []
    @Published var isLoading = false
    @Published var hasError  = false
    @Published var errorMessage: String?

    private let session: TAVSession

    init(session: TAVSession) { self.session = session }

    func load() async {
        isLoading = true
        do {
            roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
        } catch {
            errorMessage = error.localizedDescription
            hasError     = true
        }
        isLoading = false
    }

    func mark(studentId: UUID, status: AttendanceStatus) {
        // Update local state immediately for snappy UI
        if let idx = roster.firstIndex(where: { $0.studentId == studentId }) {
            roster[idx].status = status
        }

        let sessionId = session.id
        Task {
            if NetworkMonitor.shared.isConnected {
                do {
                    try await AttendanceService.shared.markAttendance(
                        sessionId: sessionId,
                        studentId: studentId,
                        status:    status
                    )
                } catch {
                    PendingAttendanceStore.shared.upsert(sessionId: sessionId, studentId: studentId, status: status)
                }
            } else {
                PendingAttendanceStore.shared.upsert(sessionId: sessionId, studentId: studentId, status: status)
            }
        }
    }

    func syncPending() async {
        do {
            try await AttendanceService.shared.syncPending()
        } catch {
            print("RosterViewModel: sync failed — \(error)")
        }
    }
}

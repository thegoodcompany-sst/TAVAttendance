import SwiftUI

struct AttendanceDetailView: View {
    let tClass: TAVClass
    @StateObject private var viewModel: AttendanceDetailViewModel
    @EnvironmentObject private var network: NetworkMonitor

    init(tClass: TAVClass) {
        self.tClass = tClass
        _viewModel = StateObject(wrappedValue: AttendanceDetailViewModel(classId: tClass.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tClass.name).font(.title2).bold()
                    if let day = tClass.scheduleDay, let time = tClass.scheduleTime {
                        Text("\(day) at \(time)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !network.isConnected {
                    Label("Offline", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .border(Color(.systemGray3), width: 1)

            // Session Control
            VStack(spacing: 12) {
                HStack {
                    Text("Today's Session").font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)

                Button(action: { Task { await viewModel.startToday() } }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(viewModel.currentSession == nil ? "Start Today's Class" : "Session Started")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.currentSession == nil ? Color.green : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .disabled(viewModel.currentSession != nil || viewModel.isStartingSession)
                .padding(.horizontal)
                .padding(.bottom)
            }

            if let session = viewModel.currentSession {
                Divider()

                // Roster with iPad Layout
                ZStack {
                    if viewModel.isLoadingRoster {
                        ProgressView("Loading roster…")
                    } else if viewModel.roster.isEmpty {
                        ContentUnavailableView(
                            "No Students",
                            systemImage: "person.3",
                            description: Text("No students are enrolled in this class.")
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: adaptiveColumnCount), spacing: 12) {
                                ForEach(viewModel.roster) { entry in
                                    AttendanceCardView(
                                        entry: entry,
                                        isOffline: !network.isConnected,
                                        onStatusChange: { newStatus in
                                            viewModel.mark(studentId: entry.studentId, status: newStatus, sessionId: session.id)
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
            } else {
                Spacer()
            }
        }
        .task {
            await viewModel.loadSessions()
        }
        .onChange(of: network.isConnected) { _, connected in
            if connected {
                Task { await viewModel.syncPending() }
            }
        }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var adaptiveColumnCount: Int {
        let horizontalSize = UIScreen.main.traitCollection.horizontalSizeClass
        return horizontalSize == .regular ? 4 : 3
    }
}

// MARK: - Attendance Card (iPad-optimized)

struct AttendanceCardView: View {
    let entry: RosterEntry
    let isOffline: Bool
    let onStatusChange: (AttendanceStatus) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(entry.fullName)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                ForEach(AttendanceStatus.allCases) { status in
                    Button(action: { onStatusChange(status) }) {
                        Text(status.shortLabel)
                            .font(.title)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(.white)
                            .background(statusColor(for: status, selected: entry.status == status))
                            .cornerRadius(6)
                    }
                }
            }

            if isOffline {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Offline")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor(for: entry.status ?? .absent, selected: true), lineWidth: entry.status == nil ? 0 : 3)
        )
    }

    private func statusColor(for status: AttendanceStatus, selected: Bool) -> Color {
        let baseColor: Color
        switch status {
        case .present: baseColor = .green
        case .absent:  baseColor = .red
        case .late:    baseColor = .orange
        case .excused: baseColor = .blue
        }
        return selected ? baseColor : baseColor.opacity(0.3)
    }
}

// MARK: - ViewModel

@MainActor
final class AttendanceDetailViewModel: ObservableObject {
    @Published var currentSession: TAVSession?
    @Published var roster: [RosterEntry] = []
    @Published var isLoadingRoster = false
    @Published var isStartingSession = false
    @Published var hasError  = false
    @Published var errorMessage: String?

    private let classId: UUID

    init(classId: UUID) {
        self.classId = classId
    }

    func loadSessions() async {
        // Try to get today's session if it exists
        do {
            let sessions = try await AttendanceService.shared.fetchSessions(classId: classId, limit: 1)
            let today = ISO8601DateFormatter.yyyyMMdd.string(from: Date())

            if let todaySession = sessions.first(where: { $0.sessionDate == today }) {
                currentSession = todaySession
                await loadRoster(for: todaySession)
            }
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func startToday() async {
        isStartingSession = true
        do {
            let session = try await AttendanceService.shared.getOrCreateTodaySession(classId: classId)
            currentSession = session
            await loadRoster(for: session)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
        isStartingSession = false
    }

    private func loadRoster(for session: TAVSession) async {
        isLoadingRoster = true
        do {
            roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
        isLoadingRoster = false
    }

    func mark(studentId: UUID, status: AttendanceStatus, sessionId: UUID) {
        // Update local state immediately for snappy UI
        if let idx = roster.firstIndex(where: { $0.studentId == studentId }) {
            roster[idx].status = status
        }

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
            print("AttendanceDetailViewModel: sync failed — \(error)")
        }
    }
}

// MARK: - Date Helpers

private extension ISO8601DateFormatter {
    static let yyyyMMdd: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

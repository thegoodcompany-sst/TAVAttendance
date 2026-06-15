import SwiftUI

struct RosterView: View {
    let session: Session
    let tavClass: TAVClass

    @Environment(\.dismiss) private var dismiss
    @State private var roster: [RosterEntry] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isEndingClass = false
    @State private var showEndClassConfirm = false
    @State private var endClassError: String? = nil
    @StateObject private var network = NetworkMonitor()
    @StateObject private var pendingStore = PendingAttendanceStore()

    // Track optimistic status updates and mark times locally for instant UI feedback
    @State private var localStatus: [UUID: AttendanceStatus] = [:]
    @State private var localMarkedAt: [UUID: Date] = [:]
    @State private var selectedStudent: RosterEntry? = nil

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let prettyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading roster…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if roster.isEmpty {
                ContentUnavailableView(
                    "No Students",
                    systemImage: "person.3",
                    description: Text("No students are enrolled in this class.")
                )
            } else {
                rosterList
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !network.isConnected {
                    Label("Offline", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                        .labelStyle(.iconOnly)
                }
                if network.isConnected && hasPendingUnsynced {
                    Button {
                        Task { await syncPending() }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isSaving)
                }
                if isEndingClass {
                    ProgressView()
                } else {
                    Button("End Class") {
                        showEndClassConfirm = true
                    }
                    .foregroundStyle(.red)
                    .disabled(isEndingClass)
                }
            }
        }
        .confirmationDialog("End Class", isPresented: $showEndClassConfirm, titleVisibility: .visible) {
            Button("End Class", role: .destructive) {
                Task { await endClass() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Students can no longer be marked after the class ends. You can resume from the class page.")
        }
        .alert("Could Not End Class", isPresented: Binding(
            get: { endClassError != nil },
            set: { if !$0 { endClassError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(endClassError ?? "")
        }
        .task {
            await loadRoster()
        }
        .onChange(of: network.isConnected) { _, connected in
            if connected {
                Task { await syncPending() }
            }
        }
    }

    // MARK: - Roster List

    private var rosterList: some View {
        List(roster) { entry in
            rosterRow(entry)
                .listRowSeparator(.visible)
                .onTapGesture { selectedStudent = entry }
        }
        .listStyle(.plain)
        .sheet(item: $selectedStudent) { entry in
            StudentProfileView(studentId: entry.studentId, fullName: entry.fullName)
        }
    }

    private func rosterRow(_ entry: RosterEntry) -> some View {
        HStack(spacing: 12) {
            // Student name + pending indicator + marked-at time
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.fullName)
                        .font(.title3)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isPending(entry) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                            .help("Unsynced change")
                    }
                }
                if let t = effectiveMarkedAt(for: entry) {
                    Text("Marked \(timeFormatter.string(from: t))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status buttons
            HStack(spacing: 8) {
                ForEach(AttendanceStatus.allCases, id: \.self) { status in
                    statusButton(status: status, entry: entry)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func statusButton(status: AttendanceStatus, entry: RosterEntry) -> some View {
        let currentStatus = effectiveStatus(for: entry)
        let isSelected = currentStatus == status

        return Button {
            Task { await markAttendance(entry: entry, status: status) }
        } label: {
            Text(label(for: status))
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(isSelected ? .white : color(for: status))
                .background(
                    isSelected
                        ? color(for: status)
                        : color(for: status).opacity(0.12)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? .clear : color(for: status).opacity(0.4),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark as \(fullLabel(for: status))")
    }

    // MARK: - Computed helpers

    private var hasPendingUnsynced: Bool {
        pendingStore.allPending().contains { $0.sessionId == session.id }
    }

    private var navigationTitle: String {
        let dateStr = formattedDate(session.sessionDate)
        return "\(dateStr) · \(tavClass.name)"
    }

    private func effectiveStatus(for entry: RosterEntry) -> AttendanceStatus? {
        // 1. Optimistic local override (set during this session)
        if let local = localStatus[entry.studentId] {
            return local
        }
        // 2. Pending store (persisted, not yet synced)
        let pending = pendingStore.allPending()
        if let record = pending.first(where: {
            $0.studentId == entry.studentId && $0.sessionId == session.id
        }) {
            return record.status
        }
        // 3. Server value
        return entry.status
    }

    private func effectiveMarkedAt(for entry: RosterEntry) -> Date? {
        if let local = localMarkedAt[entry.studentId] { return local }
        return entry.markedAt
    }

    private func isPending(_ entry: RosterEntry) -> Bool {
        pendingStore.allPending().contains {
            $0.studentId == entry.studentId && $0.sessionId == session.id
        }
    }

    // MARK: - Actions

    private func endClass() async {
        isEndingClass = true
        defer { isEndingClass = false }
        do {
            try await AttendanceService.shared.endSession(id: session.id)
            dismiss()
        } catch {
            endClassError = error.localizedDescription
        }
    }

    private func loadRoster() async {
        isLoading = true
        defer { isLoading = false }
        do {
            roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
        } catch {
            // Leave roster empty; user sees ContentUnavailableView
        }
    }

    private func markAttendance(entry: RosterEntry, status: AttendanceStatus) async {
        // Optimistic update
        localStatus[entry.studentId] = status
        localMarkedAt[entry.studentId] = Date()

        if network.isConnected {
            do {
                try await AttendanceService.shared.markAttendance(
                    sessionId: session.id,
                    studentId: entry.studentId,
                    status: status,
                    notes: nil
                )
                // Refresh first, then clear local override — clearing before the roster
                // arrives causes a flicker as SwiftUI briefly falls back to the stale
                // server value.
                if let updated = try? await AttendanceService.shared.fetchRoster(sessionId: session.id) {
                    roster = updated
                }
                localStatus.removeValue(forKey: entry.studentId)
                localMarkedAt.removeValue(forKey: entry.studentId)
            } catch {
                // Keep local override; fall through to pending store as backup
                pendingStore.add(
                    sessionId: session.id,
                    studentId: entry.studentId,
                    status: status,
                    notes: nil
                )
            }
        } else {
            pendingStore.add(
                sessionId: session.id,
                studentId: entry.studentId,
                status: status,
                notes: nil
            )
        }
    }

    private func syncPending() async {
        let unsynced = pendingStore.allPending().filter { $0.sessionId == session.id }
        guard !unsynced.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let (synced, _) = try await AttendanceService.shared.syncPending(unsynced)
            if synced > 0 {
                pendingStore.markSynced(clientMutationIds: Set(unsynced.map(\.clientMutationId)))
                roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
                for record in unsynced {
                    localStatus.removeValue(forKey: record.studentId)
                    localMarkedAt.removeValue(forKey: record.studentId)
                }
            }
        } catch {
            // Silently fail — will retry on next reconnect
        }
    }

    // MARK: - Formatting helpers

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = displayFormatter.date(from: isoDate) else { return isoDate }
        return prettyFormatter.string(from: date)
    }

    private func color(for status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .absent:  return .red
        case .late:    return .orange
        case .excused: return .gray
        }
    }

    private func label(for status: AttendanceStatus) -> String {
        switch status {
        case .present: return "P"
        case .absent:  return "A"
        case .late:    return "L"
        case .excused: return "E"
        }
    }

    private func fullLabel(for status: AttendanceStatus) -> String {
        switch status {
        case .present: return "Present"
        case .absent:  return "Absent"
        case .late:    return "Late"
        case .excused: return "Excused"
        }
    }
}

import SwiftUI

struct RosterView: View {
    let session: Session
    let tavClass: TAVClass

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var featureFlags: FeatureFlagStore
    @State private var roster: [RosterEntry] = []
    @State private var showSessionNotes = false
    @State private var sessionNotes: String? = nil
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isEndingClass = false
    @State private var showEndClassConfirm = false
    @State private var showMarkAbsentConfirm = false
    @State private var endClassError: String? = nil
    @State private var error: AppError? = nil
    @StateObject private var network = NetworkMonitor()
    @ObservedObject private var pendingStore = PendingAttendanceStore.shared

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
                if featureFlags.isEnabled(.sessionNotes) {
                    Button {
                        showSessionNotes = true
                    } label: {
                        Label("Session Notes", systemImage: "note.text")
                    }
                }
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
                if !unmarkedEntries.isEmpty {
                    Button {
                        showMarkAbsentConfirm = true
                    } label: {
                        Label("Mark Rest Absent", systemImage: "person.fill.xmark")
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
        .confirmationDialog(
            "Mark Remaining as Absent",
            isPresented: $showMarkAbsentConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark \(unmarkedEntries.count) Absent", role: .destructive) {
                Task { await markAllUnmarkedAbsent() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(unmarkedEntries.count) student\(unmarkedEntries.count == 1 ? "" : "s") have no status yet. Mark them all as Absent?")
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
        .errorAlert(error: $error)
        .sheet(isPresented: $showSessionNotes) {
            SessionNotesSheet(initial: sessionNotes ?? session.notes ?? "") { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                try await AttendanceService.shared.updateSessionNotes(id: session.id, notes: trimmed.isEmpty ? nil : trimmed)
                sessionNotes = trimmed
                Analytics.shared.track(.tap, name: "save_note", properties: ["screen": .string("roster")])
            }
        }
        .task {
            await loadRoster()
        }
        .onChange(of: network.isConnected) { _, connected in
            if connected {
                Task { await syncPending() }
            }
        }
        .analyticsScreen("roster")
    }

    // MARK: - Roster List

    private var rosterList: some View {
        List(roster) { entry in
            rosterRow(entry)
                .listRowSeparator(.visible)
                .onTapGesture { selectedStudent = entry }
        }
        .listStyle(.plain)
        .refreshable { await refreshRoster() }
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

    // PROD-03: students with no status yet (server, pending, or local override).
    private var unmarkedEntries: [RosterEntry] {
        roster.filter { effectiveStatus(for: $0) == nil }
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
            roster = try await Analytics.shared.time("roster_load", extra: ["screen": .string("roster")]) {
                try await AttendanceService.shared.fetchRoster(sessionId: session.id)
            }
        } catch {
            // Leave roster empty; user sees ContentUnavailableView
        }
    }

    // Pull-to-refresh: pull server truth and drop optimistic overrides for rows
    // that are now reflected server-side. Pending (offline) rows still show via
    // effectiveStatus's pendingStore fallback. Does not toggle isLoading so the
    // refresh spinner (not the full-screen ProgressView) is shown.
    private func refreshRoster() async {
        if let updated = try? await AttendanceService.shared.fetchRoster(sessionId: session.id) {
            roster = updated
            localStatus.removeAll()
            localMarkedAt.removeAll()
        }
    }

    private func markAllUnmarkedAbsent() async {
        for entry in unmarkedEntries {
            await markAttendance(entry: entry, status: .absent)
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
                // PERF-04: trust the optimistic localStatus instead of re-fetching
                // the whole roster on every tap (a full round-trip + list rebuild for
                // each button press). The override stays correct until the view is
                // reloaded via pull-to-refresh or reopen.
            } catch {
                // Only a transport failure (network dropped mid-request) should fall
                // through to the offline pending store. A hard rejection — RLS denial,
                // ended session — is permanent: queuing it disguises a failure as
                // "pending" and re-sends it forever. Surface those as an error and drop
                // the optimistic override so the row reverts to server truth.
                if error is URLError {
                    pendingStore.add(
                        sessionId: session.id,
                        studentId: entry.studentId,
                        status: status,
                        notes: nil
                    )
                } else {
                    localStatus.removeValue(forKey: entry.studentId)
                    localMarkedAt.removeValue(forKey: entry.studentId)
                    self.error = AppError("Could not save attendance", underlyingError: error)
                }
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
        let started = Date()
        let pendingBefore = unsynced.count
        do {
            // The RPC succeeded — every record is terminal (synced, skipped because a
            // newer server row won, or blocked because the session already ended). Clear
            // them all; leaving skipped/blocked rows in the store re-sends them forever.
            let result = try await AttendanceService.shared.syncPending(unsynced)
            Analytics.shared.track(.ops, name: "sync_result", properties: [
                "synced": .integer(result.synced),
                "skipped": .integer(result.skipped),
                "blocked_ended_session": .integer(result.blockedEndedSession),
                "pending_before": .integer(pendingBefore),
                "duration_ms": Analytics.ms(since: started),
            ])
            pendingStore.markSynced(clientMutationIds: Set(unsynced.map(\.clientMutationId)))
            roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
            for record in unsynced {
                localStatus.removeValue(forKey: record.studentId)
                localMarkedAt.removeValue(forKey: record.studentId)
            }
        } catch {
            // Only reached on a transport failure (the RPC never returned). Keep the
            // records and retry on next reconnect.
            Analytics.shared.track(.ops, name: "sync_failure", properties: [
                "message": .string("\(error)"),
                "pending_count": .integer(pendingBefore),
            ])
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

// MARK: - Session notes sheet (flag `session_notes`)

private struct SessionNotesSheet: View {
    let initial: String
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var error: AppError? = nil

    init(initial: String, onSave: @escaping (String) async throws -> Void) {
        self.initial = initial
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(12)
                .navigationTitle("Session Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save") { Task { await save() } }
                                .disabled(text == initial)
                        }
                    }
                }
                .errorAlert(error: $error)
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(text)
            dismiss()
        } catch {
            self.error = AppError("Could not save session notes", underlyingError: error)
        }
    }
}

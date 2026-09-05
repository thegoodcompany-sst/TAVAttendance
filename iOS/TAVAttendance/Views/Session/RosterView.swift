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
    @State private var rosterRevision = 0
    @State private var isEndingClass = false
    @State private var showEndClassConfirm = false
    @State private var showMarkAbsentConfirm = false
    @State private var endClassError: String? = nil
    @State private var error: AppError? = nil
    @State private var loadError: AppError? = nil
    @State private var rosterLoadFailed = false
    @StateObject private var network = NetworkMonitor()
    @ObservedObject private var pendingStore = PendingAttendanceStore.shared

    // Track optimistic status updates and mark times locally for instant UI feedback
    @State private var localStatus: [UUID: AttendanceStatus] = [:]
    @State private var localAbsenceInformed: [UUID: Bool?] = [:]
    @State private var locallyCleared: Set<UUID> = []
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
                if rosterLoadFailed {
                    ContentUnavailableView {
                        Label("Could Not Load Roster", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") { Task { await loadRoster() } }
                    }
                } else {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.3",
                        description: Text("No students are enrolled in this class.")
                    )
                }
            } else {
                rosterList
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session.endedAt == nil && featureFlags.isEnabled(.sessionNotes) {
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
                if session.endedAt == nil && !unmarkedEntries.isEmpty {
                    Button {
                        showMarkAbsentConfirm = true
                    } label: {
                        Label("Mark Rest Absent", systemImage: "person.fill.xmark")
                    }
                    .disabled(isSaving)
                }
                if session.endedAt != nil {
                    Label("Ended", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else if isEndingClass {
                    ProgressView()
                } else {
                    Button("End Class") {
                        showEndClassConfirm = true
                    }
                    .foregroundStyle(.red)
                    .disabled(isEndingClass || isSaving)
                }
            }
        }
        .confirmationDialog(
            "Mark Remaining as Absent",
            isPresented: $showMarkAbsentConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark \(unmarkedEntries.count) Absent (no notice)", role: .destructive) {
                Task { await markAllUnmarkedAbsent() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(unmarkedEntries.count) student\(unmarkedEntries.count == 1 ? " is" : "s are") Not Here Yet. Mark them all as Absent (no notice)? Bulk end-of-class marking means nobody told us in advance.")
        }
        .confirmationDialog("End Class", isPresented: $showEndClassConfirm, titleVisibility: .visible) {
            Button("End Class", role: .destructive) {
                Task { await endClass() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Students can no longer be marked after the class ends. The roster remains available for review.")
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
        .errorAlertWithRetry(error: $loadError) {
            Task { await loadRoster() }
        }
        .sheet(isPresented: $showSessionNotes) {
            SessionNotesSheet(initial: sessionNotes ?? session.notes ?? "") { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                try await AttendanceService.shared.updateSessionNotes(id: session.id, notes: trimmed.isEmpty ? nil : trimmed)
                sessionNotes = trimmed
                Analytics.shared.track(.tap, name: "save_note", properties: ["screen": .string("roster")])
            }
        }
        .task {
            if let ownerUserId = currentOwnerUserId {
                pendingStore.activateOwner(ownerUserId)
            } else {
                pendingStore.clear()
                error = AppError("Your session changed. Sign in again before marking attendance.")
            }
            await loadRoster()
            if network.isConnected { await syncPending() }
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
                .onTapGesture {
                    guard tavClass.canManageSessions == true else { return }
                    selectedStudent = entry
                }
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
                clearButton(entry: entry)
            }
        }
        .padding(.vertical, 6)
    }

    private func statusButton(status: AttendanceStatus, entry: RosterEntry) -> some View {
        let currentStatus = effectiveStatus(for: entry)
        let isSelected = currentStatus == status

        return Button {
            guard session.endedAt == nil else { return }
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
        .disabled(session.endedAt != nil || isSaving || isEndingClass)
        .accessibilityLabel("Mark as \(fullLabel(for: status, absenceInformed: effectiveAbsenceInformed(for: entry, proposed: status)))")
    }

    private func clearButton(entry: RosterEntry) -> some View {
        let isSelected = effectiveStatus(for: entry) == nil
        return Button {
            guard session.endedAt == nil else { return }
            Task { await clearAttendance(entry: entry) }
        } label: {
            Text("N")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(isSelected ? .white : .gray)
                .background(isSelected ? Color.gray : Color.gray.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(session.endedAt != nil || isSaving || isEndingClass)
        .accessibilityLabel("Not Here Yet")
    }

    // MARK: - Computed helpers

    private var currentOwnerUserId: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    private var pendingForCurrentUser: [PendingAttendanceRecord] {
        guard let ownerUserId = currentOwnerUserId else { return [] }
        return pendingStore.allPending(ownerUserId: ownerUserId)
    }

    private var hasPendingUnsynced: Bool {
        !pendingForCurrentUser.isEmpty
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
        if locallyCleared.contains(entry.studentId) { return nil }
        if let local = localStatus[entry.studentId] {
            return local
        }
        // 2. Pending store (persisted, not yet synced)
        let pending = pendingForCurrentUser
        if let record = pending.first(where: {
            $0.studentId == entry.studentId && $0.sessionId == session.id
        }) {
            return record.status
        }
        // 3. Server value
        return entry.status
    }

    /// Companion flag for `.absent`. `proposed` is used when labelling an A button
    /// that is not yet selected (accessibility only).
    private func effectiveAbsenceInformed(
        for entry: RosterEntry,
        proposed: AttendanceStatus? = nil
    ) -> Bool? {
        let status = proposed ?? effectiveStatus(for: entry)
        guard status == .absent else { return nil }
        if let local = localAbsenceInformed[entry.studentId] {
            return local
        }
        if let record = pendingForCurrentUser.first(where: {
            $0.studentId == entry.studentId && $0.sessionId == session.id
        }) {
            return record.absenceInformed
        }
        return entry.absenceInformed
    }

    private func effectiveMarkedAt(for entry: RosterEntry) -> Date? {
        if locallyCleared.contains(entry.studentId) { return nil }
        if let pending = pendingForCurrentUser.first(where: {
            $0.studentId == entry.studentId && $0.sessionId == session.id
        }), pending.status == nil { return nil }
        if let local = localMarkedAt[entry.studentId] { return local }
        return entry.markedAt
    }

    private func isPending(_ entry: RosterEntry) -> Bool {
        pendingForCurrentUser.contains {
            $0.studentId == entry.studentId && $0.sessionId == session.id
        }
    }

    // MARK: - Actions

    private func endClass() async {
        guard !isSaving, !isEndingClass else { return }
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
        let showFullScreenLoading = roster.isEmpty
        if showFullScreenLoading { isLoading = true }
        defer { if showFullScreenLoading { isLoading = false } }
        do {
            roster = try await Analytics.shared.time("roster_load", extra: ["screen": .string("roster")]) {
                try await AttendanceService.shared.fetchRoster(sessionId: session.id)
            }
            rosterLoadFailed = false
            loadError = nil
        } catch {
            rosterLoadFailed = true
            loadError = AppError("Could not load roster", underlyingError: error)
        }
    }

    // Pull-to-refresh: pull server truth and drop optimistic overrides for rows
    // that are now reflected server-side. Pending (offline) rows still show via
    // effectiveStatus's pendingStore fallback. Does not toggle isLoading so the
    // refresh spinner (not the full-screen ProgressView) is shown.
    private func refreshRoster() async {
        guard !isSaving, !isEndingClass else { return }
        let revision = rosterRevision
        do {
            let updated = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
            guard revision == rosterRevision, !isSaving else { return }
            roster = updated
            localStatus.removeAll()
            localAbsenceInformed.removeAll()
            locallyCleared.removeAll()
            localMarkedAt.removeAll()
            rosterLoadFailed = false
            loadError = nil
        } catch {
            // Keep stale rows; surface the failure instead of looking empty.
            loadError = AppError("Could not refresh roster", underlyingError: error)
        }
    }

    private func markAllUnmarkedAbsent() async {
        for entry in unmarkedEntries {
            // Bulk end-of-class remainder = nobody told us (absence_informed = false).
            await markAttendance(entry: entry, status: .absent, absenceInformed: false)
        }
    }

    @MainActor
    private func markAttendance(
        entry: RosterEntry, status: AttendanceStatus,
        absenceInformed: Bool? = nil
    ) async {
        guard !isSaving, !isEndingClass else { return }
        isSaving = true
        rosterRevision += 1
        defer { isSaving = false; rosterRevision += 1 }
        let entry = roster.first { $0.studentId == entry.studentId } ?? entry
        guard let ownerUserId = currentOwnerUserId else {
            self.error = AppError("Your session changed. Sign in again before marking attendance.")
            return
        }
        // Optimistic update
        locallyCleared.remove(entry.studentId)
        localStatus[entry.studentId] = status
        localAbsenceInformed[entry.studentId] = status == .absent ? absenceInformed : nil
        localMarkedAt[entry.studentId] = Date()

        if network.isConnected {
            do {
                let receipt = try await AttendanceService.shared.markAttendance(
                    sessionId: session.id,
                    studentId: entry.studentId,
                    status: status,
                    notes: nil,
                    absenceInformed: status == .absent ? absenceInformed : nil
                )
                if currentOwnerUserId == ownerUserId,
                   let index = roster.firstIndex(where: { $0.studentId == entry.studentId }) {
                    roster[index].acknowledge(
                        status: status, absenceInformed: absenceInformed, markedAt: receipt.markedAt)
                }
            } catch {
                // Only a transport failure (network dropped mid-request) should fall
                // through to the offline pending store. A hard rejection — RLS denial,
                // ended session — is permanent: queuing it disguises a failure as
                // "pending" and re-sends it forever. Surface those as an error and drop
                // the optimistic override so the row reverts to server truth.
                if error is URLError {
                    queuePending(
                        ownerUserId: ownerUserId, entry: entry, status: status,
                        absenceInformed: status == .absent ? absenceInformed : nil)
                } else {
                    localStatus.removeValue(forKey: entry.studentId)
                    localAbsenceInformed.removeValue(forKey: entry.studentId)
                    localMarkedAt.removeValue(forKey: entry.studentId)
                    self.error = AppError("Could not save attendance", underlyingError: error)
                }
            }
        } else {
            queuePending(
                ownerUserId: ownerUserId, entry: entry, status: status,
                absenceInformed: status == .absent ? absenceInformed : nil)
        }
    }

    @MainActor
    private func clearAttendance(entry: RosterEntry) async {
        guard !isSaving, !isEndingClass else { return }
        isSaving = true
        rosterRevision += 1
        defer { isSaving = false; rosterRevision += 1 }
        let entry = roster.first { $0.studentId == entry.studentId } ?? entry
        guard let ownerUserId = currentOwnerUserId else {
            self.error = AppError("Your session changed. Sign in again before clearing attendance.")
            return
        }
        localStatus.removeValue(forKey: entry.studentId)
        localAbsenceInformed.removeValue(forKey: entry.studentId)
        localMarkedAt.removeValue(forKey: entry.studentId)
        locallyCleared.insert(entry.studentId)

        if network.isConnected {
            do {
                try await AttendanceService.shared.clearAttendance(
                    sessionId: session.id, studentId: entry.studentId)
                if currentOwnerUserId == ownerUserId,
                   let index = roster.firstIndex(where: { $0.studentId == entry.studentId }) {
                    roster[index].acknowledge(status: nil, absenceInformed: nil, markedAt: nil)
                }
            } catch {
                if error is URLError {
                    queuePending(ownerUserId: ownerUserId, entry: entry, status: nil)
                } else {
                    locallyCleared.remove(entry.studentId)
                    self.error = AppError("Could not clear attendance", underlyingError: error)
                }
            }
        } else {
            queuePending(ownerUserId: ownerUserId, entry: entry, status: nil)
        }
    }

    private func queuePending(
        ownerUserId: UUID,
        entry: RosterEntry,
        status: AttendanceStatus?,
        absenceInformed: Bool? = nil
    ) {
        let queued = currentOwnerUserId == ownerUserId && pendingStore.add(
            ownerUserId: ownerUserId,
            sessionId: session.id,
            studentId: entry.studentId,
            status: status,
            notes: nil,
            absenceInformed: absenceInformed,
            observedMarkedAt: entry.status != nil ? entry.markedAt : nil,
            observedMarkedAtRaw: entry.status != nil ? entry.observedMarkedAtRaw : nil
        )
        guard queued else {
            localStatus.removeValue(forKey: entry.studentId)
            localAbsenceInformed.removeValue(forKey: entry.studentId)
            locallyCleared.remove(entry.studentId)
            localMarkedAt.removeValue(forKey: entry.studentId)
            self.error = AppError(
                "Attendance was not queued because the signed-in account changed. Please retry."
            )
            return
        }
    }

    private func syncPending() async {
        guard !isSaving, !isEndingClass else { return }
        guard let ownerUserId = currentOwnerUserId else {
            pendingStore.clear()
            return
        }
        let unsynced = pendingStore.allPending(ownerUserId: ownerUserId)
        guard !unsynced.isEmpty else { return }
        isSaving = true
        rosterRevision += 1
        defer { isSaving = false; rosterRevision += 1 }
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
                "skipped_conflict": .integer(result.skippedConflict),
                "pending_before": .integer(pendingBefore),
                "duration_ms": Analytics.ms(since: started),
            ])
            // Terminal outcomes (synced, skipped, blocked, conflict) must leave
            // the queue so they are not retried forever — but the tutor has to
            // see that dropped marks were not saved.
            pendingStore.markSynced(
                ownerUserId: ownerUserId,
                clientMutationIds: Set(unsynced.map(\.clientMutationId))
            )
            if result.blockedEndedSession > 0 || result.skippedConflict > 0 {
                self.error = AppError(
                    "Attendance marks were not saved. Check the website for the current register, and use paper if you still need to record them."
                )
            }
            do {
                roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id)
                for record in unsynced where record.sessionId == session.id {
                    localStatus.removeValue(forKey: record.studentId)
                    localAbsenceInformed.removeValue(forKey: record.studentId)
                    locallyCleared.remove(record.studentId)
                    localMarkedAt.removeValue(forKey: record.studentId)
                }
            } catch {
                loadError = AppError("Could not refresh roster", underlyingError: error)
            }
        } catch {
            // Only reached on a transport failure (the RPC never returned). Keep the
            // records and retry on next reconnect.
            Analytics.shared.track(.ops, name: "sync_failure", properties: [
                // Exception descriptions may echo submitted row values.
                "message": .string(String(describing: type(of: error))),
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
        }
    }

    private func label(for status: AttendanceStatus) -> String {
        switch status {
        case .present: return "P"
        case .absent:  return "A"
        case .late:    return "L"
        }
    }

    private func fullLabel(for status: AttendanceStatus, absenceInformed: Bool? = nil) -> String {
        AttendanceStatusLabel.rosterText(for: status, absenceInformed: absenceInformed)
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

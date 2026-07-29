import Combine
import LocalAuthentication
import SwiftUI
import UIKit

struct GlobalKioskView: View {
    @EnvironmentObject private var featureFlags: FeatureFlagStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("kioskPIN") private var storedPIN = ""
    @AppStorage("kioskLocked") private var isLocked = false
    @AppStorage("kioskBiometricUnlock") private var kioskBiometricUnlock = false

    @State private var entries: [KioskEntry] = []
    @State private var isLoading = true
    @State private var pendingIds: Set<UUID> = []
    @State private var showSettings = false
    @State private var showPINEntry = false
    @State private var showStudySpace = false
    @State private var showQRScanner = false

    // True when the admin unlocked the kiosk by entering a PIN this session.
    // Grants extra controls: absent marking, late→present override, present→late override.
    @StateObject private var kioskSecurity = KioskSecurityState.shared

    @State private var isSelectionMode = false
    @State private var selectedIds: Set<UUID> = []

    @State private var error: AppError? = nil

    // UX-02 search; QA-06 PIN-reset alert; UX-03 bulk confirm; UX-07 status info.
    @State private var searchText = ""
    @State private var showPINResetAlert = false
    @State private var pinNeedsRecovery = false
    @State private var pendingBulk: PendingBulkAction? = nil
    @State private var showStatusInfo = false

    // 30s kiosk auto-refresh (UX-01).
    private let autoRefresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)]

    private var isAdminMode: Bool { !isLocked && (!storedPIN.isEmpty ? kioskSecurity.isAdminUnlocked : true) }

    enum PendingBulkAction: Equatable {
        case status(AttendanceStatus)
        case dismiss

        var title: String {
            switch self {
            case .status(.late):    return "Late"
            case .status(.present): return "On Time"
            case .status(.excused): return "Not Here"
            case .status(.absent):  return "Absent"
            case .status:           return "Update"
            case .dismiss:          return "Dismissed"
            }
        }
    }

    // UX-02: filter the grid by name.
    private var filteredEntries: [KioskEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                kioskHeader

                if isLoading {
                    Spacer()
                    ProgressView("Loading students…").controlSize(.large)
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Classes Today",
                        systemImage: "calendar",
                        description: Text("No tuition classes are scheduled for today.")
                    )
                    Spacer()
                } else {
                    if !isSelectionMode { kioskSearchBar }
                    ScrollView {
                        if filteredEntries.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredEntries) { entry in
                                    KioskCard(
                                        entry: entry,
                                        isPending: pendingIds.contains(entry.studentId),
                                        isAdminMode: isAdminMode,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedIds.contains(entry.studentId),
                                        showPhoto: featureFlags.isEnabled(.studentPhotos)
                                    ) { action in
                                        Task { await handle(action, for: entry) }
                                    } onToggleSelection: {
                                        if selectedIds.contains(entry.studentId) {
                                            selectedIds.remove(entry.studentId)
                                        } else {
                                            selectedIds.insert(entry.studentId)
                                        }
                                    }
                                }
                            }
                            .padding(24)
                            .padding(.bottom, isSelectionMode ? 88 : 0)
                        }
                    }
                    .refreshable { await load() }
                }
            }

            if isSelectionMode {
                VStack {
                    Spacer()
                    selectionActionBar
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(5)
            }

            if showPINEntry {
                PINUnlockOverlay(storedPIN: storedPIN, onReset: {
                    await resetKioskPINAfterDeviceOwnerAuthentication()
                }, recoveryRequired: pinNeedsRecovery, allowBiometric: kioskBiometricUnlock) { success in
                    withAnimation(.easeInOut(duration: 0.2)) { showPINEntry = false }
                    if success {
                        isLocked = false; kioskSecurity.isAdminUnlocked = true
                        Analytics.shared.track(.ops, name: "admin_unlock")
                    }
                }
                .zIndex(10)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        // Gate navigation on effective authorization, not the persisted lock bit. On a cold
        // launch `kioskLocked=false` may survive from the previous process for a frame before
        // `.task` re-locks it; process-local admin authorization already starts false.
        .toolbar(isAdminMode ? .visible : .hidden, for: .tabBar)
        .task {
            // Migrate the one supported legacy representation. Unknown or damaged values
            // remain configured and locked; the recovery overlay requires the device
            // passcode/biometric before it will clear them.
            switch storedKioskPINDisposition(storedPIN) {
            case .legacyPlaintext:
                storedPIN = hashPIN(storedPIN)
                pinNeedsRecovery = false
            case .requiresAuthenticatedReset:
                pinNeedsRecovery = true
                kioskSecurity.isAdminUnlocked = false
                isLocked = true
                showPINEntry = true
            case .none, .currentHash:
                pinNeedsRecovery = false
            }
            // SECURITY: a configured PIN must re-lock on every launch. isAdminUnlocked
            // is @State (resets to false on restart), but kioskLocked is @AppStorage and
            // can persist `false` — leaving the kiosk "unlocked but not admin", where a
            // student could open Kiosk Settings and remove the PIN (privilege escalation).
            // Forcing locked here means admin access always requires re-entering the PIN
            // this session, matching the "does not persist across restarts" rule.
            // Guarded on !isAdminUnlocked so a .task re-run (e.g. returning to this tab)
            // never re-locks a kiosk the admin already unlocked this session — at launch
            // isAdminUnlocked is always false, so a PIN-set kiosk still boots locked.
            if shouldLockKioskOnStart(storedPIN: storedPIN) && !kioskSecurity.isAdminUnlocked {
                isLocked = true
            }
            await load()
        }
        .onReceive(autoRefresh) { _ in
            // UX-01: keep the kiosk fresh when other devices mark students. Skip
            // while the admin is mid-interaction (selection / PIN entry / loading).
            guard !isSelectionMode, !showPINEntry, !isLoading else { return }
            Task { await load() }
        }
        .alert("Kiosk PIN Reset", isPresented: $showPINResetAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The kiosk PIN was reset after device-owner authentication. Set a new PIN in Kiosk Settings before returning the device to kiosk use.")
        }
        .confirmationDialog(
            bulkConfirmTitle,
            isPresented: Binding(get: { pendingBulk != nil }, set: { if !$0 { pendingBulk = nil } }),
            titleVisibility: .visible
        ) {
            // UX-03: confirm bulk actions, naming the action + count.
            if let bulk = pendingBulk {
                Button("\(bulk.title) · \(selectedIds.count) student\(selectedIds.count == 1 ? "" : "s")",
                       role: bulk == .status(.absent) ? .destructive : nil) {
                    runBulk(bulk)
                }
            }
            Button("Cancel", role: .cancel) { pendingBulk = nil }
        } message: {
            Text("Apply “\(pendingBulk?.title ?? "")” to \(selectedIds.count) selected student\(selectedIds.count == 1 ? "" : "s")?")
        }
        .alert("Not Here vs Absent", isPresented: $showStatusInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("“Not Here” (excused) is a soft mark — the student can still tap their card to sign in. “Absent” is a firm admin mark — only an admin can undo it.")
        }
        .onChange(of: isLocked) { _, locked in
            if locked {
                kioskSecurity.isAdminUnlocked = false
                isSelectionMode = false
                selectedIds = []
                Analytics.shared.track(.ops, name: "admin_lock")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, !storedPIN.isEmpty else { return }
            // A kiosk unlock is valid only while this app is in the foreground. Dismiss
            // privileged overlays before revoking the process-local authorization so none
            // can remain interactive when the app returns.
            showSettings = false
            showStudySpace = false
            showQRScanner = false
            showPINEntry = false
            kioskSecurity.relockIfConfigured()
        }
        .sheet(isPresented: $showSettings) {
            KioskSettingsSheet(storedPIN: $storedPIN, isLocked: $isLocked)
        }
        .fullScreenCover(isPresented: $showStudySpace) {
            StudySpaceView()
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerSheet { payload in await handleScannedPayload(payload) }
        }
        .errorAlert(error: $error)
        .analyticsScreen("kiosk")
    }

    // MARK: - Header

    private var kioskHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(isSelectionMode ? "\(selectedIds.count) selected" : "Sign In")
                        .font(.system(size: 32, weight: .bold))
                        .animation(.none, value: isSelectionMode)
                    if isAdminMode && !isSelectionMode {
                        Text("ADMIN")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                    }
                }
                Text(todayString())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !entries.isEmpty && !isSelectionMode {
                let n = entries.filter(\.isAttending).count
                Text("\(n) / \(entries.count) attended")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if isSelectionMode {
                Button {
                    isSelectionMode = false
                    selectedIds = []
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: Capsule())
                }
            } else if isAdminMode && !entries.isEmpty {
                Button {
                    isSelectionMode = true
                    selectedIds = []
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
            }

            if !isSelectionMode && !entries.isEmpty && featureFlags.isEnabled(.qrSignIn) {
                // Student-facing like the card grid itself: scanning only ever runs
                // the same sign-in path a card tap would, so no admin gate needed.
                Button { showQRScanner = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
                .accessibilityLabel("Scan QR to Sign In")
            }

            if isAdminMode && !isSelectionMode && featureFlags.isEnabled(.studySpaceTracking) {
                Button { showStudySpace = true } label: {
                    Image(systemName: "studentdesk")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
                .accessibilityLabel("Study Space")
            }

            if !isAdminMode {
                // Not admin (a PIN is set and hasn't been entered this session):
                // show the unlock affordance, never the settings gear.
                Button { showPINEntry = true } label: {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
            } else if !isSelectionMode {
                // SECURITY: the gear is admin-only. Gating it on isAdminMode (not just
                // !isLocked) closes the escalation where a persisted kioskLocked=false
                // showed Settings to a student.
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.bar)
    }

    // MARK: - Selection action bar

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                // UX-07: explain the "Not Here" vs "Absent" distinction.
                Button {
                    showStatusInfo = true
                } label: {
                    Label("What's the difference?", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            HStack(spacing: 12) {
                SelectionActionButton(title: "Late", icon: "clock.badge.exclamationmark.fill", color: .orange, disabled: selectedIds.isEmpty) {
                    pendingBulk = .status(.late)
                }
                SelectionActionButton(title: "On Time", icon: "checkmark.circle.fill", color: .green, disabled: selectedIds.isEmpty) {
                    pendingBulk = .status(.present)
                }
                SelectionActionButton(title: "Not Here", icon: "person.badge.minus", color: Color(.secondaryLabel), disabled: selectedIds.isEmpty) {
                    pendingBulk = .status(.excused)
                }
                if isAdminMode {
                    SelectionActionButton(title: "Absent", icon: "person.slash.fill", color: .red, disabled: selectedIds.isEmpty) {
                        pendingBulk = .status(.absent)
                    }
                    SelectionActionButton(title: "Dismiss", icon: "figure.walk.departure", color: .purple, disabled: selectedIds.isEmpty) {
                        pendingBulk = .dismiss
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(.bar)
        }
    }

    private var bulkConfirmTitle: String {
        guard let bulk = pendingBulk else { return "" }
        return "Mark \(selectedIds.count) as \(bulk.title)?"
    }

    private func runBulk(_ bulk: PendingBulkAction) {
        pendingBulk = nil
        guard isAdminMode else { return }
        switch bulk {
        case .status(let status): Task { await applyBulkAction(status) }
        case .dismiss:            Task { await applyBulkDismiss() }
        }
    }

    // UX-02: search bar (the kiosk isn't inside a NavigationStack, so .searchable
    // isn't available — a plain field keeps it self-contained).
    private var kioskSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search students…", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func applyBulkAction(_ status: AttendanceStatus) async {
        let targets = entries.filter { selectedIds.contains($0.studentId) }
        await withTaskGroup(of: Void.self) { group in
            for entry in targets {
                group.addTask {
                    await MainActor.run { pendingIds.insert(entry.studentId) }
                    do {
                        try await AttendanceService.shared.markKioskAttendance(entry: entry, status: status)
                        await MainActor.run { updateEntry(entry.studentId, status: status) }
                    } catch {
                        await MainActor.run { self.error = AppError("Failed to update attendance", underlyingError: error) }
                    }
                    await MainActor.run { pendingIds.remove(entry.studentId) }
                }
            }
        }
        isSelectionMode = false
        selectedIds = []
    }

    private func applyBulkDismiss() async {
        let targets = entries.filter {
            selectedIds.contains($0.studentId) &&
            !$0.isDismissed &&
            ($0.status == .present || $0.status == .late)
        }
        await withTaskGroup(of: Void.self) { group in
            for entry in targets {
                // Record a dismissal for every session the student is in today,
                // mirroring how markKioskAttendance iterates all sessions.
                guard !entry.sessions.isEmpty else { continue }
                group.addTask {
                    await MainActor.run { pendingIds.insert(entry.studentId) }
                    do {
                        var lastDismissal: Dismissal? = nil
                        for session in entry.sessions {
                            lastDismissal = try await AttendanceService.shared.recordDismissal(sessionId: session.id, studentId: entry.studentId)
                        }
                        let dismissedAt = lastDismissal?.dismissedAt ?? Date()
                        await MainActor.run { updateEntry(entry.studentId, dismissedAt: dismissedAt) }
                    } catch {
                        await MainActor.run { self.error = AppError("Failed to mark dismissal", underlyingError: error) }
                    }
                    await MainActor.run { pendingIds.remove(entry.studentId) }
                }
            }
        }
        isSelectionMode = false
        selectedIds = []
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let started = Date()
        do {
            entries = try await AttendanceService.shared.fetchKioskEntries()
            let classCount = Set(entries.flatMap { $0.sessions.map(\.id) }).count
            Analytics.shared.track(.ops, name: "kiosk_load", properties: [
                "class_count": .integer(classCount),
                "entry_count": .integer(entries.count),
                "duration_ms": Analytics.ms(since: started),
            ])
            let sessionIds = entries.flatMap { $0.sessions.map { $0.id } }
            if !sessionIds.isEmpty {
                let dismissals = try await AttendanceService.shared.fetchTodaysDismissals(sessionIds: sessionIds)
                for studentId in dismissals.keys {
                    if let dismissal = dismissals[studentId],
                       let i = entries.firstIndex(where: { $0.studentId == studentId }) {
                        entries[i].dismissedAt = dismissal.dismissedAt
                    }
                }
            }
        } catch {
            self.error = AppError("Failed to load kiosk data", underlyingError: error)
        }
    }

    enum KioskAction {
        case signIn, markLate, markPresent, markAbsent, markNotHere
        case markDismissed, undoDismissal
        case addLateReason(String)
    }

    /// Student mode may only use the normal sign-in path. Keep this policy beside the
    /// mutation handler so callers cannot rely on button/context-menu visibility alone.
    static func isActionAuthorized(_ action: KioskAction, isAdminMode: Bool) -> Bool {
        isKioskActionAuthorized(action, isAdminMode: isAdminMode)
    }

    private func handle(_ action: KioskAction, for entry: KioskEntry) async {
        guard Self.isActionAuthorized(action, isAdminMode: isAdminMode) else { return }
        guard !pendingIds.contains(entry.studentId) else { return }
        pendingIds.insert(entry.studentId)
        defer { pendingIds.remove(entry.studentId) }

        do {
            switch action {
            case .signIn:
                // Per-session: late if the class has already started, present otherwise
                let worstStatus = try await AttendanceService.shared.markKioskSignIn(entry: entry)
                updateEntry(entry.studentId, status: worstStatus)

            case .markLate:
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .late)
                updateEntry(entry.studentId, status: .late)

            case .markPresent:
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .present)
                updateEntry(entry.studentId, status: .present)

            case .markAbsent:
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .absent)
                updateEntry(entry.studentId, status: .absent)

            case .markNotHere:
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .excused)
                updateEntry(entry.studentId, status: .excused)

            case .markDismissed:
                // Record a dismissal for every session the student is in today,
                // mirroring how markKioskAttendance iterates all sessions.
                guard !entry.sessions.isEmpty else { return }
                var lastDismissal: Dismissal? = nil
                for session in entry.sessions {
                    lastDismissal = try await AttendanceService.shared.recordDismissal(sessionId: session.id, studentId: entry.studentId)
                }
                updateEntry(entry.studentId, dismissedAt: lastDismissal?.dismissedAt ?? Date())

            case .undoDismissal:
                for session in entry.sessions {
                    try await AttendanceService.shared.undoDismissal(sessionId: session.id, studentId: entry.studentId)
                }
                updateEntry(entry.studentId, dismissedAt: nil)

            case .addLateReason(let reason):
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .late, lateReason: reason)
                updateEntry(entry.studentId, lateReason: reason)
            }
        } catch {
            self.error = AppError("Action failed", underlyingError: error)
        }
    }

    @MainActor
    private func resetKioskPINAfterDeviceOwnerAuthentication() async -> Bool {
        guard await Biometrics.authenticate(
            reason: "Authenticate to reset the kiosk PIN",
            policy: .deviceOwnerAuthentication
        ) else { return false }

        pinNeedsRecovery = false
        storedPIN = ""
        kioskSecurity.isAdminUnlocked = true
        isLocked = false
        withAnimation(.easeInOut(duration: 0.2)) { showPINEntry = false }
        showPINResetAlert = true
        Analytics.shared.track(.ops, name: "admin_pin_reset")
        return true
    }

    /// QR sign-in (flag `qr_sign_in`): resolves the payload to a kiosk entry and runs
    /// the exact same path as tapping the card. Returns the feedback line shown in the scanner.
    private func handleScannedPayload(_ payload: String) async -> String {
        guard let id = AttendanceService.studentId(fromQRPayload: payload) else {
            Analytics.shared.track(.ops, name: "qr_scan", properties: ["ok": .bool(false)])
            return String(localized: "Not a student QR code")
        }
        Analytics.shared.track(.ops, name: "qr_scan", properties: ["ok": .bool(true)])
        guard let entry = entries.first(where: { $0.studentId == id }) else {
            return String(localized: "Student not found for today's classes")
        }
        guard !entry.isDismissed else {
            return "\(entry.fullName) — \(String(localized: "already dismissed"))"
        }
        switch entry.status {
        case nil, .excused:
            await handle(.signIn, for: entry)
            if let updated = entries.first(where: { $0.studentId == id }),
               let status = updated.status, status != .excused {
                let label = status == .late ? String(localized: "Late") : String(localized: "On Time")
                return "\(updated.fullName) — \(label)"
            }
            return String(localized: "Sign-in failed — please try again")
        case .absent:
            return "\(entry.fullName) — \(String(localized: "marked Absent, ask a teacher"))"
        default:
            return "\(entry.fullName) — \(String(localized: "already signed in"))"
        }
    }

    private func updateEntry(_ studentId: UUID, status: AttendanceStatus) {
        if let i = entries.firstIndex(where: { $0.studentId == studentId }) {
            entries[i].status = status
            entries[i].markedAt = Date()
        }
    }

    private func updateEntry(_ studentId: UUID, dismissedAt: Date?) {
        if let i = entries.firstIndex(where: { $0.studentId == studentId }) {
            entries[i].dismissedAt = dismissedAt
        }
    }

    private func updateEntry(_ studentId: UUID, lateReason: String?) {
        if let i = entries.firstIndex(where: { $0.studentId == studentId }) {
            entries[i].lateReason = lateReason
        }
    }

    private func todayString() -> String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: Date())
    }
}

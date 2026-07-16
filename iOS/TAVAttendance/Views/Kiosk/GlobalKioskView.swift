import CommonCrypto
import Combine
import SwiftUI
import UIKit

struct GlobalKioskView: View {
    @EnvironmentObject private var featureFlags: FeatureFlagStore

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
                    // QA-06 recovery: reachable only after a lockout. If the stored hash
                    // can never validate (e.g. after a device restore changed the salt),
                    // this clears the PIN and unlocks so the kiosk isn't permanently
                    // bricked. Staff then set a new PIN via Settings.
                    withAnimation(.easeInOut(duration: 0.2)) { showPINEntry = false }
                    storedPIN = ""
                    isLocked = false
                    showPINResetAlert = true
                }, allowBiometric: kioskBiometricUnlock) { success in
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
        .toolbar(isLocked ? .hidden : .visible, for: .tabBar)
        .task {
            // Migrate plaintext 4-digit PINs stored before hashing was introduced.
            // Any stored value that is not a recognised "v1:..." hash is treated as
            // plaintext if it is exactly 4 digits; anything else is cleared so the
            // admin is prompted to set a new PIN rather than being permanently locked out.
            if !storedPIN.isEmpty && !storedPIN.hasPrefix("v1:") {
                if storedPIN.count == 4 && storedPIN.allSatisfy(\.isNumber) {
                    storedPIN = hashPIN(storedPIN)
                } else {
                    // QA-06: an unrecognised PIN format is cleared (so the admin isn't
                    // locked out), but warn them so the kiosk isn't silently left open.
                    storedPIN = ""
                    showPINResetAlert = true
                }
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
            if !storedPIN.isEmpty && !kioskSecurity.isAdminUnlocked {
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
            Text("The saved kiosk PIN was in an unrecognised format and has been cleared. The kiosk is currently unlocked — please set a new PIN in Kiosk Settings.")
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

    private func handle(_ action: KioskAction, for entry: KioskEntry) async {
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

// MARK: - Selection action button

private struct SelectionActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(disabled ? Color(.tertiaryLabel) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(disabled ? Color(.systemGray6) : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Student card

private struct KioskCard: View {
    let entry: KioskEntry
    let isPending: Bool
    let isAdminMode: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let showPhoto: Bool
    let onAction: (GlobalKioskView.KioskAction) -> Void
    let onToggleSelection: () -> Void

    @State private var showLateReason = false
    @State private var showLateReasonAlert = false
    @State private var showMarkPresentConfirm = false
    @State private var showAbsentSignInConfirm = false   // UX-04
    @State private var photoURL: URL? = nil               // PROD-04

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private var statusColor: Color {
        if entry.isDismissed { return .purple }
        switch entry.status {
        case .present: return .green
        case .late:    return .orange
        case .absent:  return .red
        case .excused, nil: return Color(.tertiaryLabel)
        }
    }

    private var statusIcon: String {
        if entry.isDismissed { return "arrow.up.right.circle.fill" }
        switch entry.status {
        case .present: return "checkmark.circle.fill"
        case .late:    return "clock.badge.exclamationmark.fill"
        case .absent:  return "person.slash.fill"
        case .excused: return "person.badge.minus"
        case nil:      return "person.circle"
        }
    }

    private var statusLabel: String {
        if entry.isDismissed {
            if let t = entry.dismissedAt {
                return "Dismissed \(Self.timeFormatter.string(from: t))"
            }
            return "Dismissed"
        }
        switch entry.status {
        case .present: return "On Time"
        case .late:    return "Late"
        case .absent:  return "Absent"
        case .excused: return "Not Here"
        // A11Y-02: give the unsigned state a text label too, so it doesn't rely on
        // a grey icon alone to be distinguished from "Not Here".
        case nil:      return "Not Signed In"
        }
    }

    private var underlyingStatusLabel: String? {
        guard entry.isDismissed else { return nil }
        switch entry.status {
        case .present: return "On Time"
        case .late:    return "Late"
        default:       return nil
        }
    }

    private var canTap: Bool {
        if isSelectionMode { return true }
        guard !entry.isDismissed else { return false }
        // UX-04: absent cards are tappable for students too, to raise an "Are you
        // here?" confirmation (an escape hatch from an accidental absent mark).
        return entry.status == nil || entry.status == .excused || entry.status == .absent ||
            (isAdminMode && entry.status == .late)
    }

    var body: some View {
        Button {
            if isSelectionMode {
                onToggleSelection()
                return
            }
            if entry.status == nil || entry.status == .excused {
                onAction(.signIn)
            } else if entry.status == .absent && !isAdminMode {
                showAbsentSignInConfirm = true   // UX-04
            } else if isAdminMode && entry.status != .present {
                showMarkPresentConfirm = true
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                                .padding(10)
                        }
                    }

                if isPending {
                    ProgressView().controlSize(.large)
                } else {
                    VStack(spacing: 8) {
                        if showPhoto, entry.avatarUrl != nil {
                            avatarView   // PROD-04
                        } else {
                            Image(systemName: statusIcon)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(statusColor)
                                .accessibilityLabel(statusLabel)
                        }

                        Text(entry.fullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        // A11Y-02: always show a text status label (including the
                        // unsigned state) so colour/icon isn't the only signal.
                        VStack(spacing: 2) {
                                Text(statusLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor)
                                if let secondary = underlyingStatusLabel {
                                    Text(secondary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !entry.isDismissed, let status = entry.status {
                                    if status != .excused, let t = entry.markedAt {
                                        Text(Self.timeFormatter.string(from: t))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                    }
                                    if isAdminMode && status != .present && status != .excused {
                                        Text("Tap to change…")
                                            .font(.caption2.italic())
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 1)
                                    }
                                }
                                if isAdminMode, let reason = entry.lateReason, !entry.isDismissed {
                                    Button {
                                        showLateReasonAlert = true
                                    } label: {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 1)
                                    .alert("Late Reason", isPresented: $showLateReasonAlert) {
                                        Button("OK", role: .cancel) {}
                                    } message: {
                                        Text(reason)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 16)
                }
            }
            .frame(minHeight: 140)
            .scaleEffect(isPending ? 0.96 : 1.0)
            .animation(.spring(response: 0.25), value: isPending)
        }
        .buttonStyle(.plain)
        .disabled(isPending || !canTap)
        .animation(.spring(response: 0.3), value: entry.status)
        .animation(.spring(response: 0.3), value: entry.isDismissed)
        .animation(.spring(response: 0.2), value: isSelected)
        .contextMenu { if !isSelectionMode { contextMenuContent } }
        .confirmationDialog(
            "Mark \(entry.fullName) as On Time?",
            isPresented: $showMarkPresentConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark as On Time") { onAction(.markPresent) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will override their current status.")
        }
        .sheet(isPresented: $showLateReason) {
            LateReasonSheet { reason in
                onAction(.addLateReason(reason))
                showLateReason = false
            } onCancel: {
                showLateReason = false
            }
        }
        .alert("Marked Absent", isPresented: $showAbsentSignInConfirm) {
            // UX-04 escape hatch — but "Absent" is a hard admin mark that a student
            // must NOT be able to undo themselves (see CLAUDE.md). So this is purely
            // informational: it explains the state and routes the student to a teacher,
            // who can override via admin mode. No attendance change happens here.
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(entry.fullName) is marked Absent. Please ask a teacher to sign you in.")
        }
    }

    // PROD-04: student photo with a small status badge, loaded via a signed URL.
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = photoURL {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.systemGray5)
                    }
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(3)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
        }
        .accessibilityLabel(statusLabel)
        .task {
            if photoURL == nil, let path = entry.avatarUrl {
                photoURL = try? await AttendanceService.shared.signedStudentPhotoURL(path: path)
            }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if !entry.isDismissed {
            if entry.status != .late && entry.status != .absent {
                Button {
                    onAction(.markLate)
                } label: {
                    Label("Mark as Late", systemImage: "clock.badge.exclamationmark")
                }
            }
            if entry.status == .late || entry.status == .present {
                Button {
                    onAction(.markNotHere)
                } label: {
                    Label("Mark as Not Here", systemImage: "person.badge.minus")
                }
            }
            if isAdminMode {
                if (entry.status == .present || entry.status == .late) && !entry.isDismissed {
                    Button {
                        onAction(.markDismissed)
                    } label: {
                        Label("Mark as Dismissed", systemImage: "figure.walk.departure")
                    }
                }
                if entry.status == .late {
                    Button {
                        showLateReason = true
                    } label: {
                        Label(entry.lateReason == nil ? "Add Late Reason…" : "Edit Late Reason…", systemImage: "pencil")
                    }
                }
                if entry.status != .present && entry.status != nil && entry.status != .excused {
                    Button {
                        onAction(.markPresent)
                    } label: {
                        Label("Mark as On Time", systemImage: "checkmark.circle")
                    }
                }
                if entry.status != .absent {
                    Button(role: .destructive) {
                        onAction(.markAbsent)
                    } label: {
                        Label("Mark as Absent", systemImage: "person.slash")
                    }
                }
            }
        } else if isAdminMode {
            Button {
                onAction(.undoDismissal)
            } label: {
                Label("Undo Dismissal", systemImage: "arrow.uturn.left")
            }
        }
    }
}

// MARK: - Late reason sheet

private struct LateReasonSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    private let presets = ["Traffic", "Bus delay", "Overslept", "Sick", "Family", "Other"]
    @State private var selected: String? = nil
    @State private var freeText = ""

    private var isOther: Bool { selected == "Other" }
    private var effectiveText: String { isOther ? freeText : (selected ?? freeText) }
    private var canSave: Bool { !effectiveText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Select a reason or enter your own.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            selected = preset
                            if preset != "Other" { freeText = "" }
                        } label: {
                            Text(preset)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(selected == preset ? Color.accentColor : Color(.systemGray5), in: Capsule())
                                .foregroundStyle(selected == preset ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if isOther || selected == nil {
                    TextField("Enter reason…", text: $freeText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Late Reason")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(effectiveText.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Kiosk settings sheet

private struct KioskSettingsSheet: View {
    @Binding var storedPIN: String
    @Binding var isLocked: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showPINSetup = false
    @AppStorage("kioskBiometricUnlock") private var kioskBiometricUnlock = false

    // SECURITY: Change PIN / Remove PIN both re-authenticate against the current PIN
    // before taking effect, so reaching this sheet is not enough to alter the PIN.
    private enum SecureAction { case change, remove }
    @State private var challenge: SecureAction? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section {
                        if storedPIN.isEmpty {
                            Label("No PIN set — kiosk is unlocked", systemImage: "lock.open")
                                .foregroundStyle(.secondary)
                            Button("Set Kiosk PIN…") { showPINSetup = true }
                        } else {
                            Label("PIN configured", systemImage: "lock.fill")
                                .foregroundStyle(.green)
                            Button("Change PIN…") { challenge = .change }
                            Button("Lock Kiosk Now") {
                                isLocked = true
                                dismiss()
                            }
                            Button("Remove PIN", role: .destructive) {
                                challenge = .remove
                            }
                        }
                    } header: {
                        Text("Kiosk Lock")
                    } footer: {
                        Text("When locked the tab bar is hidden and only the sign-in grid is shown. Tap the lock icon and enter the PIN to unlock and access admin controls.")
                    }

                    if !storedPIN.isEmpty,
                       let name = Biometrics.biometryName(policy: .deviceOwnerAuthenticationWithBiometrics) {
                        Section {
                            Toggle("Allow \(name) Unlock", isOn: $kioskBiometricUnlock)
                        } footer: {
                            Text("Anyone enrolled in \(name) on this iPad can unlock admin mode. Enable only if this device's \(name) is staff-only. The PIN always remains available.")
                        }
                    }
                }

                // Re-authentication overlay for the destructive PIN actions.
                if let action = challenge {
                    PINUnlockOverlay(storedPIN: storedPIN, onReset: {
                        // Recovery is disabled inside settings — an admin who can open
                        // this sheet is already unlocked; only cancel the challenge.
                        challenge = nil
                    }) { success in
                        challenge = nil
                        guard success else { return }
                        switch action {
                        case .change: showPINSetup = true
                        case .remove: storedPIN = ""; isLocked = false
                        }
                    }
                    .zIndex(10)
                    .transition(.opacity)
                }
            }
            .navigationTitle("Kiosk Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPINSetup) {
                PINSetupSheet(storedPIN: $storedPIN)
            }
        }
    }
}

// MARK: - PIN setup (custom number pad)

private struct PINSetupSheet: View {
    @Binding var storedPIN: String
    @Environment(\.dismiss) private var dismiss

    @State private var firstPIN = ""
    @State private var secondPIN = ""
    @State private var step = 1
    @State private var error = ""

    private var current: String { step == 1 ? firstPIN : secondPIN }

    var body: some View {
        NavigationStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
                .overlay(
                    VStack(spacing: 40) {
                        Spacer()

                        VStack(spacing: 16) {
                            Text(step == 1 ? "Choose a 4-digit PIN" : "Confirm your PIN")
                                .font(.title2.bold())

                            HStack(spacing: 20) {
                                ForEach(0..<4) { i in
                                    Circle()
                                        .fill(current.count > i ? Color.accentColor : Color(.systemGray4))
                                        .frame(width: 18, height: 18)
                                }
                            }

                            if !error.isEmpty {
                                Text(error).foregroundStyle(.red).font(.subheadline)
                            }
                        }

                        numPad(tint: .accentColor) { digit in append(digit) } onDelete: { deleteLast() }

                        Spacer()
                    }
                    .padding(32)
                )
            .navigationTitle(storedPIN.isEmpty ? "Set PIN" : "Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func append(_ d: String) {
        error = ""
        if step == 1 {
            guard firstPIN.count < 4 else { return }
            firstPIN += d
            if firstPIN.count == 4 { step = 2 }
        } else {
            guard secondPIN.count < 4 else { return }
            secondPIN += d
            if secondPIN.count == 4 { confirm() }
        }
    }

    private func deleteLast() {
        error = ""
        if step == 2 { if secondPIN.isEmpty { step = 1 } else { secondPIN.removeLast() } }
        else if !firstPIN.isEmpty { firstPIN.removeLast() }
    }

    private func confirm() {
        if firstPIN == secondPIN { storedPIN = hashPIN(firstPIN); dismiss() }
        else { error = "PINs don't match — try again"; firstPIN = ""; secondPIN = ""; step = 1 }
    }
}

// MARK: - PIN unlock overlay

private struct PINUnlockOverlay: View {
    let storedPIN: String
    // QA-06 recovery: invoked from the lockout screen when the PIN can never validate.
    var onReset: (() -> Void)? = nil
    // Kiosk-settings opt-in: offers Face ID/Touch ID as an alternative door. Success
    // does not touch the PIN failure counters — it's simply another way in.
    var allowBiometric = false
    let onDone: (Bool) -> Void

    // Persisted so a device restart can't reset the lockout counter.
    @AppStorage("kioskFailedAttempts") private var failedAttempts: Int = 0
    @AppStorage("kioskLockoutUntil") private var lockoutUntil: Double = 0

    @State private var entered = ""
    @State private var error = ""
    @State private var secondsRemaining: Int = 0

    // Lock after this many CUMULATIVE failures; the counter is only reset by a correct
    // PIN, never by a lockout expiring (that was the brute-force hole: 5 tries / 30s
    // forever). Past the threshold, each further wrong entry backs off exponentially.
    private let attemptsBeforeLockout = 5

    private var isLockedOut: Bool { Date().timeIntervalSince1970 < lockoutUntil }

    /// Exponential backoff keyed on cumulative failures: 5→30s, 6→1m, 7→2m … capped 1h.
    private func lockoutDuration(forFailures failures: Int) -> Double {
        let over = max(0, failures - attemptsBeforeLockout)
        return min(30.0 * pow(2.0, Double(over)), 3600)
    }

    private var lockoutMessage: String {
        let s = secondsRemaining
        if s >= 60 { return "Try again in \(s / 60)m \(s % 60)s" }
        return "Try again in \(s)s"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                    Text("Admin Access")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text(isLockedOut ? "Too many attempts" : "Enter PIN to unlock")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if isLockedOut {
                    VStack(spacing: 12) {
                        Text(lockoutMessage)
                            .font(.title2.bold())
                            .foregroundStyle(.orange)
                        Button("Cancel") { onDone(false) }
                            .foregroundStyle(.white.opacity(0.7))
                        // QA-06: an escape hatch reachable only once locked out, so a
                        // legit admin whose hash can't validate (e.g. after a device
                        // restore) isn't permanently bricked. Confirmed to avoid taps.
                        if let onReset {
                            Button("Forgot PIN — Reset Kiosk", role: .destructive) {
                                failedAttempts = 0
                                lockoutUntil = 0
                                onReset()
                            }
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                        }
                    }
                } else {
                    HStack(spacing: 20) {
                        ForEach(0..<4) { i in
                            Circle()
                                .fill(entered.count > i ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 18, height: 18)
                        }
                    }

                    if !error.isEmpty {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }

                    numPad(tint: .white,
                           onDigit: { digit in appendUnlock(digit) },
                           onDelete: { if !entered.isEmpty { entered.removeLast() } },
                           leading: { AnyView(
                               Button("Cancel") { onDone(false) }
                                   .foregroundStyle(.white.opacity(0.7))
                                   .frame(width: 80, height: 80)
                           ) })

                    // No auto-prompt: the overlay can be opened accidentally by a student,
                    // so biometrics require an explicit tap.
                    if allowBiometric,
                       let name = Biometrics.biometryName(policy: .deviceOwnerAuthenticationWithBiometrics) {
                        Button {
                            Task {
                                if await Biometrics.authenticate(
                                    reason: "Unlock kiosk admin mode",
                                    policy: .deviceOwnerAuthenticationWithBiometrics) {
                                    onDone(true)
                                }
                            }
                        } label: {
                            Label("Unlock with \(name)",
                                  systemImage: name == "Touch ID" ? "touchid" : "faceid")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(48)
        }
        .onAppear { tick() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in tick() }
    }

    private func tick() {
        let remaining = lockoutUntil - Date().timeIntervalSince1970
        secondsRemaining = remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    private func appendUnlock(_ d: String) {
        guard !isLockedOut, entered.count < 4 else { return }
        error = ""
        entered += d
        if entered.count == 4 {
            if hashPIN(entered) == storedPIN {
                failedAttempts = 0
                lockoutUntil = 0
                onDone(true)
            } else {
                // Cumulative: never reset the counter on lockout, only on success.
                failedAttempts += 1
                let attemptsLeft = attemptsBeforeLockout - failedAttempts
                if attemptsLeft <= 0 {
                    // Exponential backoff grows with total failures; the counter is left
                    // in place so the next wrong entry after the lockout locks longer.
                    lockoutUntil = Date().timeIntervalSince1970 + lockoutDuration(forFailures: failedAttempts)
                    tick()
                    entered = ""
                } else {
                    error = "Incorrect PIN — \(attemptsLeft) attempt\(attemptsLeft == 1 ? "" : "s") left"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { entered = ""; error = "" }
                }
            }
        }
    }
}

// MARK: - PIN hashing

// PBKDF2-SHA256 with 10,000 iterations and a device-tied salt.
// "v1:" prefix distinguishes hashed values from any legacy plaintext.
// The identifierForVendor ties the hash to this device installation,
// making offline brute-force against a UserDefaults dump impractical without
// also knowing the device UUID.
//
// ponytail: DEFERRED (finding 8a) — move the hash + a RANDOM salt to the Keychain.
// Not done here because it can't be build-verified in this environment and a blind
// migration risks bricking live kiosks. The exact migration to implement:
//   1. Generate a random 32-byte salt once; store {salt, hash} as one keychain item
//      under service "sg.tava.kiosk", account "pinHash",
//      accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
//   2. Change hashPIN to take the stored salt (not identifierForVendor) so a device
//      restore no longer changes the salt — the "v1:" hash keeps validating.
//   3. On first launch: if UserDefaults "kioskPIN" holds a "v1:" hash and no keychain
//      item exists, copy it into the keychain (keeping the OLD idfv salt for that
//      migrated value via a "v1:"/"v2:" version tag), THEN remove the UserDefaults key.
//   4. New PINs are written "v2:" (random-salt) only. Keep validating "v1:" during a
//      deprecation window. Do NOT delete the UserDefaults copy until the keychain
//      write is confirmed (read-back) to avoid a half-migration lockout.
// Until then, the QA-06 reset affordance (finding 8c) is the in-app recovery path.
private func hashPIN(_ pin: String) -> String {
    let salt = (UIDevice.current.identifierForVendor?.uuidString ?? "tava-kiosk-fallback").utf8
    var derived = [UInt8](repeating: 0, count: 32)
    CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2),
        pin, pin.utf8.count,
        Array(salt), salt.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
        10_000,
        &derived, derived.count
    )
    return "v1:" + derived.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Shared number pad builder

private func numPad(
    tint: Color,
    onDigit: @escaping (String) -> Void,
    onDelete: @escaping () -> Void,
    leading: (() -> AnyView)? = nil
) -> some View {
    let rows: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"]]
    return VStack(spacing: 16) {
        ForEach(rows.indices, id: \.self) { i in
            HStack(spacing: 16) {
                ForEach(rows[i], id: \.self) { d in
                    padKey(d, tint: tint, action: { onDigit(d) })
                }
            }
        }
        HStack(spacing: 16) {
            if let l = leading {
                l()
            } else {
                Spacer().frame(width: 80, height: 80)
            }
            padKey("0", tint: tint, action: { onDigit("0") })
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: 80, height: 80)
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        }
    }
}

private func padKey(_ digit: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(digit)
            .font(.title.weight(.light))
            .frame(width: 80, height: 80)
            .background(tint.opacity(tint == .white ? 0.15 : 0.1), in: Circle())
            .foregroundStyle(tint == .white ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
}

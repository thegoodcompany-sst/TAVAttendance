import CommonCrypto
import SwiftUI
import UIKit

struct GlobalKioskView: View {
    @AppStorage("kioskPIN") private var storedPIN = ""
    @AppStorage("kioskLocked") private var isLocked = false

    @State private var entries: [KioskEntry] = []
    @State private var isLoading = true
    @State private var pendingIds: Set<UUID> = []
    @State private var showSettings = false
    @State private var showPINEntry = false

    // True when the admin unlocked the kiosk by entering a PIN this session.
    // Grants extra controls: absent marking, late→present override, present→late override.
    @State private var isAdminUnlocked = false

    @State private var isSelectionMode = false
    @State private var selectedIds: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)]

    private var isAdminMode: Bool { !isLocked && (!storedPIN.isEmpty ? isAdminUnlocked : true) }

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
                        "No Students",
                        systemImage: "person.3",
                        description: Text("No students are enrolled in any active class.")
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(entries) { entry in
                                KioskCard(
                                    entry: entry,
                                    isPending: pendingIds.contains(entry.studentId),
                                    isAdminMode: isAdminMode,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedIds.contains(entry.studentId)
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
                PINUnlockOverlay(storedPIN: storedPIN) { success in
                    withAnimation(.easeInOut(duration: 0.2)) { showPINEntry = false }
                    if success { isLocked = false; isAdminUnlocked = true }
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
                    storedPIN = ""  // unrecognised format — require PIN reset
                }
            }
            await load()
        }
        .onChange(of: isLocked) { _, locked in
            if locked {
                isAdminUnlocked = false
                isSelectionMode = false
                selectedIds = []
            }
        }
        .sheet(isPresented: $showSettings) {
            KioskSettingsSheet(storedPIN: $storedPIN, isLocked: $isLocked)
        }
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

            if isLocked {
                Button { showPINEntry = true } label: {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
            } else if !isSelectionMode {
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
            HStack(spacing: 12) {
                SelectionActionButton(title: "Late", icon: "clock.badge.exclamationmark.fill", color: .orange, disabled: selectedIds.isEmpty) {
                    Task { await applyBulkAction(.late) }
                }
                SelectionActionButton(title: "On Time", icon: "checkmark.circle.fill", color: .green, disabled: selectedIds.isEmpty) {
                    Task { await applyBulkAction(.present) }
                }
                SelectionActionButton(title: "Not Here", icon: "person.badge.minus", color: Color(.secondaryLabel), disabled: selectedIds.isEmpty) {
                    Task { await applyBulkAction(.excused) }
                }
                if isAdminMode {
                    SelectionActionButton(title: "Absent", icon: "person.slash.fill", color: .red, disabled: selectedIds.isEmpty) {
                        Task { await applyBulkAction(.absent) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(.bar)
        }
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
                    } catch {}
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
        do {
            entries = try await AttendanceService.shared.fetchKioskEntries()
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
        } catch {}
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
                try await AttendanceService.shared.markKioskSignIn(entry: entry)
                // Compute the aggregate status to show in the card
                let worstStatus = computeSignInStatus(entry: entry)
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
                guard let sessionId = entry.sessions.first?.id else { return }
                let dismissal = try await AttendanceService.shared.recordDismissal(sessionId: sessionId, studentId: entry.studentId)
                updateEntry(entry.studentId, dismissedAt: dismissal.dismissedAt ?? Date())

            case .undoDismissal:
                for session in entry.sessions {
                    try await AttendanceService.shared.undoDismissal(sessionId: session.id, studentId: entry.studentId)
                }
                updateEntry(entry.studentId, dismissedAt: nil)

            case .addLateReason(let reason):
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .late, lateReason: reason)
                updateEntry(entry.studentId, lateReason: reason)
            }
        } catch {}
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

    /// Mirrors the per-session logic in AttendanceService.markKioskSignIn so the card shows correctly.
    private func computeSignInStatus(entry: KioskEntry) -> AttendanceStatus {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        for session in entry.sessions {
            if let startedAt = session.startedAt, now > startedAt {
                return .late
            }
            guard let timeStr = session.scheduleTime else { continue }
            let parts = timeStr.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { continue }
            comps.hour = parts[0]; comps.minute = parts[1]; comps.second = 0
            if let start = cal.date(from: comps), now > start { return .late }
        }
        return .present
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
    let onAction: (GlobalKioskView.KioskAction) -> Void
    let onToggleSelection: () -> Void

    @State private var showLateReason = false
    @State private var showLateReasonAlert = false
    @State private var showMarkPresentConfirm = false

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
        case nil:      return ""
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
        return entry.status == nil || entry.status == .excused ||
            (isAdminMode && (entry.status == .late || entry.status == .absent))
    }

    var body: some View {
        Button {
            if isSelectionMode {
                onToggleSelection()
                return
            }
            if entry.status == nil || entry.status == .excused {
                onAction(.signIn)
            } else if isAdminMode && entry.status != .present {
                showMarkPresentConfirm = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                        .padding(10)
                }

                if isPending {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(statusColor)

                        Text(entry.fullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        if entry.isDismissed || entry.status != nil {
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if storedPIN.isEmpty {
                        Label("No PIN set — kiosk is unlocked", systemImage: "lock.open")
                            .foregroundStyle(.secondary)
                        Button("Set Kiosk PIN…") { showPINSetup = true }
                    } else {
                        Label("PIN configured", systemImage: "lock.fill")
                            .foregroundStyle(.green)
                        Button("Change PIN…") { showPINSetup = true }
                        Button("Lock Kiosk Now") {
                            isLocked = true
                            dismiss()
                        }
                        Button("Remove PIN", role: .destructive) {
                            storedPIN = ""; isLocked = false
                        }
                    }
                } header: {
                    Text("Kiosk Lock")
                } footer: {
                    Text("When locked the tab bar is hidden and only the sign-in grid is shown. Tap the lock icon and enter the PIN to unlock and access admin controls.")
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
    let onDone: (Bool) -> Void

    // Persisted so a device restart can't reset the lockout counter.
    @AppStorage("kioskFailedAttempts") private var failedAttempts: Int = 0
    @AppStorage("kioskLockoutUntil") private var lockoutUntil: Double = 0

    @State private var entered = ""
    @State private var error = ""
    @State private var secondsRemaining: Int = 0

    private let maxAttempts = 5
    private let lockoutSeconds: Double = 30

    private var isLockedOut: Bool { Date().timeIntervalSince1970 < lockoutUntil }

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
                        Text("Try again in \(secondsRemaining)s")
                            .font(.title2.bold())
                            .foregroundStyle(.orange)
                        Button("Cancel") { onDone(false) }
                            .foregroundStyle(.white.opacity(0.7))
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
                failedAttempts += 1
                let attemptsLeft = maxAttempts - failedAttempts
                if attemptsLeft <= 0 {
                    lockoutUntil = Date().timeIntervalSince1970 + lockoutSeconds
                    failedAttempts = 0
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

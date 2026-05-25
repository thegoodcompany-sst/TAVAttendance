import SwiftUI

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
                                    isAdminMode: isAdminMode
                                ) { action in
                                    Task { await handle(action, for: entry) }
                                }
                            }
                        }
                        .padding(24)
                    }
                    .refreshable { await load() }
                }
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
        .task { await load() }
        .onChange(of: isLocked) { _, locked in
            if locked { isAdminUnlocked = false }
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
                    Text("Sign In")
                        .font(.system(size: 32, weight: .bold))
                    if isAdminMode {
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

            if !entries.isEmpty {
                let n = entries.filter(\.isAttending).count
                Text("\(n) / \(entries.count) attended")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if isLocked {
                Button { showPINEntry = true } label: {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5), in: Circle())
                }
            } else {
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

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { entries = try await AttendanceService.shared.fetchKioskEntries() } catch {}
    }

    enum KioskAction { case signIn, markLate, markPresent, markAbsent, markNotHere }

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
                // Excused = "not here today" — card returns to grey/tappable so student can still sign in
                try await AttendanceService.shared.markKioskAttendance(entry: entry, status: .excused)
                updateEntry(entry.studentId, status: .excused)
            }
        } catch {}
    }

    private func updateEntry(_ studentId: UUID, status: AttendanceStatus) {
        if let i = entries.firstIndex(where: { $0.studentId == studentId }) {
            entries[i].status = status
            entries[i].markedAt = Date()
        }
    }

    /// Mirrors the per-session logic in AttendanceService.markKioskSignIn so the card shows correctly.
    private func computeSignInStatus(entry: KioskEntry) -> AttendanceStatus {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        for session in entry.sessions {
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

// MARK: - Student card

private struct KioskCard: View {
    let entry: KioskEntry
    let isPending: Bool
    let isAdminMode: Bool
    let onAction: (GlobalKioskView.KioskAction) -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private var cardColor: Color {
        switch entry.status {
        case .present: return .green
        case .late:    return .orange
        case .absent:  return .red
        case .excused: return .gray
        case nil:      return Color(.secondarySystemGroupedBackground)
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .present: return "checkmark"
        case .late:    return "clock.badge.exclamationmark"
        case .absent:  return "person.slash"
        case .excused: return "person.badge.minus"  // grayed out, still tappable
        case nil:      return "person"
        }
    }

    private var statusLabel: String {
        switch entry.status {
        case .present: return "On Time"
        case .late:    return "Late"
        case .absent:  return "Absent"
        case .excused: return "Excused"
        case nil:      return ""
        }
    }

    private var isColoured: Bool { entry.status != nil && entry.status != .excused }
    private var canTap: Bool {
        entry.status == nil || entry.status == .excused ||
        (isAdminMode && (entry.status == .late || entry.status == .absent))
    }

    var body: some View {
        Button {
            if entry.status == nil || entry.status == .excused {
                onAction(.signIn)
            } else if isAdminMode && entry.status != .present {
                onAction(.markPresent)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(isColoured
                          ? AnyShapeStyle(cardColor)
                          : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                    .shadow(color: isColoured ? cardColor.opacity(0.35) : .black.opacity(0.07),
                            radius: isColoured ? 8 : 4, x: 0, y: 3)

                // Admin-mode indicator border on marked cards
                if isAdminMode && entry.status != nil {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                }

                if isPending {
                    ProgressView().controlSize(.large)
                        .tint(isColoured ? .white : .accentColor)
                } else {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isColoured
                                      ? Color.white.opacity(0.25)
                                      : Color.accentColor.opacity(0.1))
                                .frame(width: 56, height: 56)
                            Image(systemName: statusIcon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isColoured ? .white : .accentColor)
                        }

                        Text(entry.fullName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isColoured ? .white : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        if let status = entry.status {
                            VStack(spacing: 2) {
                                if status == .excused {
                                    // Show as grey "Not Here" — card stays tappable to re-sign-in
                                    Text("Not Here")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(statusLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    if let t = entry.markedAt {
                                        Text(Self.timeFormatter.string(from: t))
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    if isAdminMode && status != .present {
                                        Text("Tap to mark On Time")
                                            .font(.caption2.italic())
                                            .foregroundStyle(.white.opacity(0.6))
                                            .padding(.top, 1)
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
        .contextMenu { contextMenuContent }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        // Anyone can force-late or mark not-here via long press
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
        // Admin-only overrides
        if isAdminMode {
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
        if firstPIN == secondPIN { storedPIN = firstPIN; dismiss() }
        else { error = "PINs don't match — try again"; firstPIN = ""; secondPIN = ""; step = 1 }
    }
}

// MARK: - PIN unlock overlay

private struct PINUnlockOverlay: View {
    let storedPIN: String
    let onDone: (Bool) -> Void

    @State private var entered = ""
    @State private var error = ""

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
                    Text("Enter PIN to unlock")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

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
            .padding(48)
        }
    }

    private func appendUnlock(_ d: String) {
        guard entered.count < 4 else { return }
        error = ""
        entered += d
        if entered.count == 4 {
            if entered == storedPIN { onDone(true) }
            else {
                error = "Incorrect PIN"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { entered = ""; error = "" }
            }
        }
    }
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

import SwiftUI

// Two-step kiosk: students pick their class, then tap their name.
struct GlobalKioskView: View {

    // Which step we're on
    enum KioskStep {
        case pickClass
        case signIn(session: Session, tavClass: TAVClass)
    }

    @State private var step: KioskStep = .pickClass
    @State private var classes: [TAVClass] = []
    @State private var isLoading = true
    @State private var busyClassId: UUID? = nil

    private let dateStr: String = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }()

    private let classColumns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)]

    var body: some View {
        Group {
            switch step {
            case .pickClass:
                classPickerScreen
            case .signIn(let session, let tavClass):
                KioskSignInScreen(
                    session: session,
                    tavClass: tavClass,
                    onBack: { withAnimation(.easeInOut(duration: 0.3)) { step = .pickClass } }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isSigningIn)
        .task { await loadClasses() }
    }

    private var isSigningIn: Bool {
        if case .signIn = step { return true }
        return false
    }

    // MARK: - Class picker screen

    private var classPickerScreen: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome")
                            .font(.system(size: 36, weight: .bold))
                        Text("Select your class to sign in")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(todayLong())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(.bar)

                if isLoading {
                    Spacer()
                    ProgressView("Loading classes…").controlSize(.large)
                    Spacer()
                } else if classes.isEmpty {
                    Spacer()
                    ContentUnavailableView("No Active Classes",
                                          systemImage: "calendar.badge.exclamationmark",
                                          description: Text("No classes are currently active."))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: classColumns, spacing: 20) {
                            ForEach(classes) { cls in
                                ClassPickerCard(
                                    tavClass: cls,
                                    isLoading: busyClassId == cls.id
                                ) {
                                    Task { await selectClass(cls) }
                                }
                            }
                        }
                        .padding(32)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar) // hide tab bar when kiosk is active? no — keep it so admin can switch
    }

    // MARK: - Actions

    private func loadClasses() async {
        isLoading = true
        do {
            classes = try await AttendanceService.shared.fetchMyClasses()
        } catch {}
        isLoading = false
    }

    private func selectClass(_ cls: TAVClass) async {
        busyClassId = cls.id
        defer { busyClassId = nil }
        do {
            let session = try await AttendanceService.shared.getOrCreateSession(
                classId: cls.id, date: dateStr)
            withAnimation(.easeInOut(duration: 0.3)) {
                step = .signIn(session: session, tavClass: cls)
            }
        } catch {}
    }

    private func todayLong() -> String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: Date())
    }
}

// MARK: - Class picker card

private struct ClassPickerCard: View {
    let tavClass: TAVClass
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

                if isLoading {
                    ProgressView().controlSize(.large)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "rectangle.3.group.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            if let day = tavClass.scheduleDay {
                                Text(day)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        Text(tavClass.name)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        let sub = [tavClass.subject, tavClass.level].compactMap { $0 }.joined(separator: " · ")
                        if !sub.isEmpty {
                            Text(sub)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let time = tavClass.scheduleTime {
                            Label(time, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 150)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Sign-in screen (second step)

private struct KioskSignInScreen: View {
    let session: Session
    let tavClass: TAVClass
    let onBack: () -> Void

    @State private var roster: [RosterEntry] = []
    @State private var isLoading = true
    @State private var pendingIds: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 16)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                signInHeader

                if isLoading {
                    Spacer()
                    ProgressView("Loading class list…").controlSize(.large)
                    Spacer()
                } else if roster.isEmpty {
                    Spacer()
                    ContentUnavailableView("No Students", systemImage: "person.3",
                                          description: Text("No students are enrolled in this class."))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(roster) { entry in
                                StudentSignInCard(
                                    entry: entry,
                                    isPending: pendingIds.contains(entry.studentId)
                                ) { Task { await markPresent(entry: entry) } }
                            }
                        }
                        .padding(24)
                    }
                }
            }

            // Back button — top left
            Button(action: onBack) {
                Label("All Classes", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .task { await loadRoster() }
    }

    private var presentCount: Int { roster.filter { $0.status == .present }.count }

    private var signInHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign In")
                    .font(.largeTitle.bold())
                Text(tavClass.name)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(presentCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("/ \(roster.count) present")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func loadRoster() async {
        isLoading = true
        defer { isLoading = false }
        do { roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id) } catch {}
    }

    private func markPresent(entry: RosterEntry) async {
        guard entry.status != .present, !pendingIds.contains(entry.studentId) else { return }
        pendingIds.insert(entry.studentId)
        do {
            try await AttendanceService.shared.markAttendance(
                sessionId: session.id, studentId: entry.studentId, status: .present)
            if let idx = roster.firstIndex(where: { $0.studentId == entry.studentId }) {
                roster[idx].status = .present
            }
        } catch {}
        pendingIds.remove(entry.studentId)
    }
}

// MARK: - Student sign-in card (shared with KioskView)

struct StudentSignInCard: View {
    let entry: RosterEntry
    let isPending: Bool
    let onTap: () -> Void

    private var isPresent: Bool { entry.status == .present }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(isPresent ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                    .shadow(color: isPresent ? .green.opacity(0.3) : .black.opacity(0.07),
                            radius: isPresent ? 8 : 4, x: 0, y: 3)

                if isPending {
                    ProgressView().controlSize(.large).tint(isPresent ? .white : .accentColor)
                } else {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isPresent ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.1))
                                .frame(width: 52, height: 52)
                            Image(systemName: isPresent ? "checkmark" : "person")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isPresent ? .white : .accentColor)
                        }
                        Text(entry.fullName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isPresent ? .white : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if isPresent {
                            Text("Signed in")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                }
            }
            .frame(minHeight: 130)
            .scaleEffect(isPending ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: isPending)
        }
        .buttonStyle(.plain)
        .disabled(isPresent || isPending)
        .animation(.spring(response: 0.3), value: isPresent)
    }
}

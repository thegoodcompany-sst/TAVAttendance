import SwiftUI

// Unified route for all navigation out of SessionListView
private enum SessionRoute: Identifiable {
    case live(Session)
    case detail(Session)
    case edit(Session)

    var id: UUID {
        switch self {
        case .live(let s), .detail(let s), .edit(let s): return s.id
        }
    }
}

struct SessionListView: View {
    let tavClass: TAVClass

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var featureFlags: FeatureFlagStore
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var isStartingClass = false
    @State private var isEndingClass = false
    @State private var route: SessionRoute? = nil
    @State private var showingEnrollment = false
    @State private var showingTutorAssignment = false
    @State private var showingPastSessionForm = false
    @StateObject private var network = NetworkMonitor()
    @State private var error: AppError? = nil

    // Punctuality stats
    @State private var punctuality: PunctualitySummary? = nil

    // Substitution
    @State private var tutors: [Profile] = []
    @State private var sessionForSubstitute: Session? = nil

    private var isAdmin: Bool { authManager.currentProfile?.role == "admin" }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private let prettyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    // MARK: - Computed punctuality percentages

    private var onTimePct: String {
        guard let p = punctuality, p.totalCount > 0 else { return "—" }
        return "\(Int((Double(p.presentCount) / Double(p.totalCount) * 100).rounded()))%"
    }
    private var latePct: String {
        guard let p = punctuality, p.totalCount > 0 else { return "—" }
        return "\(Int((Double(p.lateCount) / Double(p.totalCount) * 100).rounded()))%"
    }
    private var absentPct: String {
        guard let p = punctuality, p.totalCount > 0 else { return "—" }
        return "\(Int((Double(p.absentCount) / Double(p.totalCount) * 100).rounded()))%"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Class-wide analytics remain owner/admin-only. Substitutes
                    // receive just the sessions covered by their appointment.
                    if tavClass.canManageSessions == true {
                        Section {
                            HStack {
                                statCol("On Time", value: onTimePct, color: .green)
                                Divider()
                                statCol("Late", value: latePct, color: .orange)
                                Divider()
                                statCol("Absent", value: absentPct, color: .red)
                            }
                            .frame(height: 56)
                        } header: { Text("Last 30 Days") }
                    }

                    // Today's class controls — state-driven
                    Section {
                        todayClassControls
                    }

                    if pastSessions.isEmpty {
                        Section {
                            Text("No past sessions yet.").foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Past Sessions") {
                            ForEach(pastSessions) { session in
                                Button {
                                    route = .detail(session)
                                } label: {
                                    HStack {
                                        sessionRow(session)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    if tavClass.canManageSessions == true
                                        && featureFlags.isEnabled(.retrospectiveSessions) {
                                        Button {
                                            route = .edit(session)
                                        } label: {
                                            Label("Edit Session", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    } else if tavClass.canManageSessions == true {
                                        Button {
                                            sessionForSubstitute = session
                                        } label: {
                                            Label("Substitute", systemImage: "person.2.badge.key")
                                        }
                                        .tint(.indigo)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tavClass.name)
        .analyticsScreen("session_list")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: Binding(
            get: { route != nil },
            set: { if !$0 { route = nil } }
        )) {
            switch route {
            case .live(let s):
                RosterView(session: s, tavClass: tavClass)
            case .detail(let s):
                SessionDetailView(session: s, tavClass: tavClass)
            case .edit(let s):
                HistoricalSessionEditorView(session: s, tavClass: tavClass) { _ in
                    Task { await loadSessions() }
                }
            case nil:
                EmptyView()
            }
        }
        .toolbar {
            if tavClass.canManageSessions == true
                && featureFlags.isEnabled(.retrospectiveSessions) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingPastSessionForm = true
                    } label: {
                        Label("Add Past Session", systemImage: "calendar.badge.plus")
                    }
                }
            }
            if isAdmin {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingTutorAssignment = true
                    } label: {
                        Label("Assign Teacher", systemImage: "person.2.badge.gearshape")
                    }
                    Button {
                        showingEnrollment = true
                    } label: {
                        Label("Manage Students", systemImage: "person.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEnrollment) {
            EnrollmentView(tavClass: tavClass)
        }
        .sheet(isPresented: $showingTutorAssignment) {
            TutorAssignmentView(tavClass: tavClass)
        }
        .sheet(isPresented: $showingPastSessionForm) {
            PastSessionFormView(
                tavClass: tavClass, sessions: sessions, tutors: tutors,
                onCreated: { session in
                    route = .edit(session)
                    Task { await loadSessions() }
                },
                onExisting: { session in route = .edit(session) })
        }
        .sheet(item: $sessionForSubstitute) { session in
            SubstituteTutorSheet(session: session, tutors: tutors) {
                Task { await loadSessions() }
            }
        }
        // loadSessions on every appear so the today-section updates after popping from RosterView
        .onAppear {
            Task { await loadSessions() }
        }
        .task {
            if tavClass.canManageSessions == true {
                await loadPunctuality()
                await loadTutors()
            }
        }
        .errorAlert(error: $error)
    }

    // MARK: - Today class controls

    @ViewBuilder
    private var todayClassControls: some View {
        if tavClass.canOperateTodaySession != true {
            Label(
                "Recent substitute access is read-only. You are not assigned to today's session.",
                systemImage: "clock.badge.exclamationmark"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        } else if let session = todaySession {
            if session.endedAt != nil {
                // Ended sessions are immutable; staff may still review the roster.
                openRow(session: session, title: "View Ended Class", subtitle: "Ended \(timeFormatter.string(from: session.endedAt!))")
            } else if session.startedAt != nil {
                // Class in progress — return or end
                openRow(session: session, title: "Return to Class", subtitle: "Started \(timeFormatter.string(from: session.startedAt!))")
                endClassRow(session: session)
            } else {
                // Session row exists but not yet started
                startRow
            }
        } else {
            startRow
        }
    }

    private var startRow: some View {
        Button {
            guard !isStartingClass else { return }
            Task { await startTodayClass() }
        } label: {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("Start Today's Class")
                    .font(.headline)
                Spacer()
                if isStartingClass { ProgressView() }
            }
            .foregroundStyle(isStartingClass ? Color.gray : Color.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(isStartingClass ? Color.blue.opacity(0.5) : Color.blue)
                .padding(.vertical, 2)
        )
        .disabled(isStartingClass)
    }

    private func openRow(session: Session, title: LocalizedStringKey, subtitle: String) -> some View {
        Button {
            guard !isStartingClass else { return }
            Task { await openTodayClass(session: session) }
        } label: {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
                if isStartingClass { ProgressView() }
            }
            .foregroundStyle(isStartingClass ? Color.gray : Color.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(isStartingClass ? Color.blue.opacity(0.5) : Color.blue)
                .padding(.vertical, 2)
        )
        .disabled(isStartingClass || isEndingClass)
    }

    private func endClassRow(session: Session) -> some View {
        Button {
            guard !isEndingClass else { return }
            Task { await endTodayClass(session: session) }
        } label: {
            HStack {
                Spacer()
                Label(isEndingClass ? "Ending…" : "End Class", systemImage: "stop.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .foregroundStyle(isEndingClass ? .gray : .red)
                    .background((isEndingClass ? Color.gray : Color.red).opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                (isEndingClass ? Color.gray : Color.red).opacity(0.4),
                                lineWidth: 1
                            )
                    )
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .disabled(isEndingClass || isStartingClass)
    }

    // MARK: - Subviews

    private func statCol(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var todaySession: Session? {
        sessions.first(where: { $0.sessionDate == todayDateString() })
    }

    private var pastSessions: [Session] {
        sessions.filter { $0.sessionDate < todayDateString() }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedDate(session.sessionDate)).font(.headline)
                Spacer()
                if let subId = session.subTutorId,
                   let tutor = tutors.first(where: { $0.id == subId }) {
                    Text("Sub: \(tutor.fullName.split(separator: " ").first.map(String.init) ?? tutor.fullName)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                if let startedAt = session.startedAt {
                    Label(timeFormatter.string(from: startedAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let topic = session.topic, !topic.isEmpty {
                    Text(topic).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await AttendanceService.shared.fetchSessions(for: tavClass.id)
        } catch {
            self.error = AppError("Failed to load sessions", underlyingError: error)
        }
        await autoEndIfExpired()
    }

    /// Auto-end the session when scheduled end time has passed, but only if the session
    /// started before the scheduled end (guards against off-schedule/makeup classes).
    private func autoEndIfExpired() async {
        guard tavClass.canOperateTodaySession == true,
              let session = sessions.first(where: { $0.sessionDate == todayDateString() }),
              let startedAt = session.startedAt,
              session.endedAt == nil,
              let endTime = computeScheduledEndTime(),
              startedAt < endTime,
              Date() > endTime else { return }
        do {
            try await AttendanceService.shared.endSession(id: session.id)
            sessions = try await AttendanceService.shared.fetchSessions(for: tavClass.id)
        } catch {
            self.error = AppError("Failed to auto-end session", underlyingError: error)
        }
    }

    /// Returns today's scheduled end time as a wall-clock Date, or nil if not configured.
    private func computeScheduledEndTime() -> Date? {
        guard let timeStr = tavClass.scheduleTime else { return nil }
        let parts = timeStr.split(separator: ":").map(String.init)
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let start = Calendar.current.date(from: comps) else { return nil }
        return start.addingTimeInterval(TimeInterval(tavClass.durationMinutes * 60))
    }

    private func startTodayClass() async {
        guard tavClass.canOperateTodaySession == true else { return }
        isStartingClass = true
        defer { isStartingClass = false }
        Analytics.shared.track(.tap, name: "start_session", properties: ["screen": .string("session_list")])
        do {
            let session = try await AttendanceService.shared.getOrCreateTodaySession(
                classId: tavClass.id)
            if session.startedAt == nil {
                try await AttendanceService.shared.startSession(id: session.id)
            }
            await loadSessions()
            let fresh = sessions.first(where: { $0.id == session.id }) ?? session
            route = .live(fresh)
        } catch {
            self.error = AppError("Failed to start class", underlyingError: error)
        }
    }

    private func openTodayClass(session: Session) async {
        isStartingClass = true
        defer { isStartingClass = false }
        do {
            sessions = try await AttendanceService.shared.fetchSessions(for: tavClass.id)
            let fresh = sessions.first(where: { $0.id == session.id }) ?? session
            route = .live(fresh)
        } catch {
            self.error = AppError("Failed to open class", underlyingError: error)
        }
    }

    private func endTodayClass(session: Session) async {
        guard tavClass.canOperateTodaySession == true else { return }
        isEndingClass = true
        defer { isEndingClass = false }
        Analytics.shared.track(.tap, name: "end_session", properties: ["screen": .string("session_list")])
        do {
            try await AttendanceService.shared.endSession(id: session.id)
            sessions = try await AttendanceService.shared.fetchSessions(for: tavClass.id)
        } catch {
            self.error = AppError("Failed to end class", underlyingError: error)
        }
    }

    private func loadPunctuality() async {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -30, to: to) ?? to
        do {
            punctuality = try await AttendanceService.shared.fetchClassPunctuality(
                classId: tavClass.id, from: from, to: to)
        } catch {
            self.error = AppError("Failed to load punctuality stats", underlyingError: error)
        }
    }

    private func loadTutors() async {
        do {
            tutors = try await AttendanceService.shared.fetchTutors()
        } catch {
            self.error = AppError("Failed to load tutors", underlyingError: error)
        }
    }

    private func todayDateString() -> String { dateFormatter.string(from: Date()) }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = dateFormatter.date(from: isoDate) else { return isoDate }
        return prettyFormatter.string(from: date)
    }
}

// MARK: - SubstituteTutorSheet

private struct SubstituteTutorSheet: View {
    let session: Session
    let tutors: [Profile]
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var error: AppError? = nil

    var body: some View {
        NavigationStack {
            List {
                if session.subTutorId != nil {
                    Section {
                        Button(role: .destructive) {
                            Task { await setSubstitute(nil) }
                        } label: {
                            Label("Remove Substitute", systemImage: "person.badge.minus")
                        }
                        .disabled(isSaving)
                    }
                }

                Section("Select Substitute") {
                    ForEach(tutors) { tutor in
                        Button {
                            Task { await setSubstitute(tutor.id) }
                        } label: {
                            HStack {
                                Text(tutor.fullName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if session.subTutorId == tutor.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                                if isSaving { ProgressView() }
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Set Substitute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .errorAlert(error: $error)
        }
    }

    private func setSubstitute(_ tutorId: UUID?) async {
        isSaving = true
        do {
            try await AttendanceService.shared.setSessionSubstitute(sessionId: session.id, tutorId: tutorId)
            onSave()
            dismiss()
        } catch {
            // Don't dismiss on failure — surface it so the change isn't silently lost.
            self.error = AppError("Could not update the substitute tutor.", underlyingError: error)
        }
        isSaving = false
    }
}

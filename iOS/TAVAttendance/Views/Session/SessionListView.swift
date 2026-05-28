import SwiftUI

struct SessionListView: View {
    let tavClass: TAVClass

    @EnvironmentObject var authManager: AuthManager
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var isStartingClass = false
    @State private var navigationDestination: Session? = nil
    @State private var showingEnrollment = false
    @State private var showingTutorAssignment = false
    @StateObject private var network = NetworkMonitor()

    // Punctuality stats (Task 1)
    @State private var punctuality: PunctualitySummary? = nil

    // Substitution (Task 2)
    @State private var tutors: [Profile] = []
    @State private var sessionForSubstitute: Session? = nil

    private var isAdmin: Bool { authManager.currentProfile?.role == "admin" }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private let displayFormatter: DateFormatter = {
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
                    // Task 1: Punctuality header card
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

                    Section {
                        startTodayButton
                    }

                    if sessions.isEmpty {
                        Section {
                            Text("No past sessions yet.").foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Past Sessions") {
                            ForEach(sessions) { session in
                                NavigationLink(value: session) {
                                    sessionRow(session)
                                }
                                // Task 2: Substitute swipe action
                                .swipeActions(edge: .leading) {
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
        .navigationTitle(tavClass.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Session.self) { session in
            RosterView(session: session, tavClass: tavClass)
        }
        .toolbar {
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
        // Task 2: Substitute sheet
        .sheet(item: $sessionForSubstitute) { session in
            SubstituteTutorSheet(session: session, tutors: tutors) {
                Task { await loadSessions() }
            }
        }
        .task {
            await loadSessions()
            await loadPunctuality()
            await loadTutors()
        }
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

    @ViewBuilder
    private var startTodayButton: some View {
        let inProgress = todaySession?.startedAt != nil
        Button {
            guard !isStartingClass else { return }
            Task { await startTodayClass() }
        } label: {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(inProgress ? "Class In Progress" : "Start Today's Class")
                        .font(.headline)
                    if inProgress, let s = todaySession?.startedAt {
                        Text("Started \(timeFormatter.string(from: s))")
                            .font(.caption)
                            .opacity(0.85)
                    }
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
                .fill(isStartingClass ? Color.blue.opacity(0.5) : (inProgress ? Color.green : Color.blue))
                .padding(.vertical, 2)
        )
        .disabled(isStartingClass)
        .navigationDestination(isPresented: Binding(
            get: { navigationDestination != nil },
            set: { if !$0 { navigationDestination = nil } }
        )) {
            if let s = navigationDestination { RosterView(session: s, tavClass: tavClass) }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedDate(session.sessionDate)).font(.headline)
                Spacer()
                // Task 2: sub badge
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
            if let topic = session.topic, !topic.isEmpty {
                Text(topic).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do { sessions = try await AttendanceService.shared.fetchSessions(for: tavClass.id) } catch {}
    }

    private func loadPunctuality() async {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -30, to: to) ?? to
        do {
            punctuality = try await AttendanceService.shared.fetchClassPunctuality(
                classId: tavClass.id, from: from, to: to)
        } catch {}
    }

    private func loadTutors() async {
        do { tutors = try await AttendanceService.shared.fetchTutors() } catch {}
    }

    private func startTodayClass() async {
        isStartingClass = true
        defer { isStartingClass = false }
        do {
            let session = try await AttendanceService.shared.getOrCreateSession(
                classId: tavClass.id, date: todayDateString())
            try? await AttendanceService.shared.startSession(id: session.id)
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            } else {
                await loadSessions()
            }
            navigationDestination = session
        } catch {}
    }

    private func todayDateString() -> String { dateFormatter.string(from: Date()) }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = displayFormatter.date(from: isoDate) else { return isoDate }
        return prettyFormatter.string(from: date)
    }
}

// MARK: - SubstituteTutorSheet (Task 2)

private struct SubstituteTutorSheet: View {
    let session: Session
    let tutors: [Profile]
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

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
        }
    }

    private func setSubstitute(_ tutorId: UUID?) async {
        isSaving = true
        do {
            try await AttendanceService.shared.setSessionSubstitute(sessionId: session.id, tutorId: tutorId)
            onSave()
            dismiss()
        } catch {}
        isSaving = false
    }
}

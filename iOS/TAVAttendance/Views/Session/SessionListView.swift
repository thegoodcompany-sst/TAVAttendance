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

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
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
        .task { await loadSessions() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var startTodayButton: some View {
        Button {
            guard !isStartingClass else { return }
            Task { await startTodayClass() }
        } label: {
            HStack {
                Image(systemName: "play.circle.fill").font(.title2)
                Text("Start Today's Class").font(.headline)
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
        .navigationDestination(isPresented: Binding(
            get: { navigationDestination != nil },
            set: { if !$0 { navigationDestination = nil } }
        )) {
            if let s = navigationDestination { RosterView(session: s, tavClass: tavClass) }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDate(session.sessionDate)).font(.headline)
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

    private func startTodayClass() async {
        isStartingClass = true
        defer { isStartingClass = false }
        do {
            let session = try await AttendanceService.shared.getOrCreateSession(
                classId: tavClass.id, date: todayDateString())
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
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

import SwiftUI

struct SessionListView: View {
    let tClass: TAVClass
    @StateObject private var viewModel: SessionListViewModel

    init(tClass: TAVClass) {
        self.tClass = tClass
        _viewModel = StateObject(wrappedValue: SessionListViewModel(classId: tClass.id))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading sessions…")
            } else {
                List {
                    Section {
                        Button("Start Today's Class") {
                            Task { await viewModel.startToday() }
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                        .padding(.vertical, 4)
                    }

                    Section("Recent Sessions") {
                        if viewModel.sessions.isEmpty {
                            Text("No sessions yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.sessions) { session in
                                NavigationLink(value: session) {
                                    SessionRowView(session: session)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tClass.name)
        .navigationDestination(for: TAVSession.self) { session in
            RosterView(session: session, className: tClass.name)
        }
        .task { await viewModel.load() }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Row

private struct SessionRowView: View {
    let session: TAVSession
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.sessionDate).font(.headline)
            if let topic = session.topic {
                Text(topic).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ViewModel

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var sessions: [TAVSession] = []
    @Published var isLoading = false
    @Published var hasError  = false
    @Published var errorMessage: String?
    @Published var navigateTo: TAVSession?

    private let classId: UUID

    init(classId: UUID) { self.classId = classId }

    func load() async {
        isLoading = true
        do {
            sessions = try await AttendanceService.shared.fetchSessions(classId: classId)
        } catch {
            errorMessage = error.localizedDescription
            hasError     = true
        }
        isLoading = false
    }

    func startToday() async {
        isLoading = true
        do {
            let session = try await AttendanceService.shared.getOrCreateTodaySession(classId: classId)
            // Trigger navigation
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            }
            navigateTo = session
        } catch {
            errorMessage = error.localizedDescription
            hasError     = true
        }
        isLoading = false
    }
}

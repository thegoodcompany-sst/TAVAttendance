import SwiftUI

struct ClassListView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var viewModel = ClassListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading classes…")
                } else if viewModel.classes.isEmpty {
                    ContentUnavailableView(
                        "No Classes",
                        systemImage: "book.closed",
                        description: Text("You have no active class assignments.")
                    )
                } else {
                    List(viewModel.classes) { tClass in
                        NavigationLink(value: tClass) {
                            ClassRowView(tClass: tClass)
                        }
                    }
                }
            }
            .navigationTitle("My Classes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        Task { try? await auth.signOut() }
                    }
                }
            }
            .navigationDestination(for: TAVClass.self) { tClass in
                SessionListView(tClass: tClass)
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: $viewModel.hasError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }
}

// MARK: - Row

private struct ClassRowView: View {
    let tClass: TAVClass

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tClass.name).font(.headline)
            HStack(spacing: 8) {
                if let day = tClass.scheduleDay {
                    Label(day, systemImage: "calendar")
                }
                if let time = tClass.scheduleTime {
                    Label(String(time.prefix(5)), systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
final class ClassListViewModel: ObservableObject {
    @Published var classes: [TAVClass] = []
    @Published var isLoading = false
    @Published var hasError  = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        do {
            classes = try await AttendanceService.shared.fetchClasses()
        } catch {
            errorMessage = error.localizedDescription
            hasError     = true
        }
        isLoading = false
    }
}

import SwiftUI

struct AttendanceTakerView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var viewModel = AttendanceTakerViewModel()

    var body: some View {
        NavigationSplitView {
            // Sidebar: Class List
            Group {
                if viewModel.isLoadingClasses {
                    ProgressView("Loading classes…")
                } else if viewModel.classes.isEmpty {
                    ContentUnavailableView(
                        "No Classes",
                        systemImage: "book.closed",
                        description: Text("You have no active class assignments.")
                    )
                } else {
                    List(viewModel.classes, selection: $viewModel.selectedClass) { tClass in
                        ClassSidebarRow(tClass: tClass)
                            .tag(tClass)
                    }
                }
            }
            .navigationTitle("Classes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        Task { try? await auth.signOut() }
                    }
                }
            }
        } detail: {
            if let selectedClass = viewModel.selectedClass {
                AttendanceDetailView(tClass: selectedClass)
            } else {
                ContentUnavailableView(
                    "Select a Class",
                    systemImage: "hand.raised.fill",
                    description: Text("Choose a class from the sidebar to mark attendance.")
                )
            }
        }
        .task { await viewModel.loadClasses() }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Sidebar Row

private struct ClassSidebarRow: View {
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
final class AttendanceTakerViewModel: ObservableObject {
    @Published var classes: [TAVClass] = []
    @Published var selectedClass: TAVClass?
    @Published var isLoadingClasses = false
    @Published var hasError  = false
    @Published var errorMessage: String?

    func loadClasses() async {
        isLoadingClasses = true
        do {
            classes = try await AttendanceService.shared.fetchClasses()
            if !classes.isEmpty {
                selectedClass = classes.first
            }
        } catch {
            errorMessage = error.localizedDescription
            hasError     = true
        }
        isLoadingClasses = false
    }
}

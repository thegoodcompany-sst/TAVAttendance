import SwiftUI

struct ClassListView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var network = NetworkMonitor()

    @State private var classes: [TAVClass] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingAddClass = false
    @State private var editingClass: TAVClass?
    @State private var classToDelete: TAVClass?
    @State private var showingDeleteConfirm = false

    private var isAdmin: Bool { authManager.currentProfile?.role == "admin" }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading classes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Retry") { Task { await loadClasses() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if classes.isEmpty {
                    ContentUnavailableView(
                        "No Classes",
                        systemImage: "person.3",
                        description: Text(isAdmin ? "Tap + to create the first class." : "You have no active classes assigned.")
                    )
                } else {
                    List(classes) { cls in
                        NavigationLink(destination: SessionListView(tavClass: cls)) {
                            ClassRow(tavClass: cls)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isAdmin {
                                Button(role: .destructive) {
                                    classToDelete = cls
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                Button {
                                    editingClass = cls
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("My Classes")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !network.isConnected {
                        Label("Offline", systemImage: "wifi.slash")
                            .foregroundColor(.orange)
                            .labelStyle(.iconOnly)
                    }
                    if isAdmin {
                        Button {
                            showingAddClass = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        Task { try? await authManager.signOut() }
                    } label: {
                        Text("Sign Out")
                    }
                }
            }
        }
        .task { await loadClasses() }
        .sheet(isPresented: $showingAddClass) {
            ClassFormView(mode: .create) { Task { await loadClasses() } }
        }
        .sheet(item: $editingClass) { cls in
            ClassFormView(mode: .edit(cls)) { Task { await loadClasses() } }
        }
        .confirmationDialog(
            "Remove \"\(classToDelete?.name ?? "class")\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let cls = classToDelete { Task { await deleteClass(cls) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The class will be hidden. Sessions and attendance records are preserved.")
        }
    }

    private func loadClasses() async {
        isLoading = true
        error = nil
        do {
            classes = try await AttendanceService.shared.fetchMyClasses()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteClass(_ cls: TAVClass) async {
        do {
            try await AttendanceService.shared.deleteClass(id: cls.id)
            await loadClasses()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct ClassRow: View {
    let tavClass: TAVClass

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tavClass.name)
                .font(.headline)

            let subjectLevel = [tavClass.subject, tavClass.level].compactMap { $0 }.joined(separator: " · ")
            if !subjectLevel.isEmpty {
                Text(subjectLevel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            let schedule = [tavClass.scheduleDay, tavClass.scheduleTime].compactMap { $0 }.joined(separator: " ")
            if !schedule.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(schedule)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

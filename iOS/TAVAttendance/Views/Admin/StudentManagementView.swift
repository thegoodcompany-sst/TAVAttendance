import SwiftUI

struct StudentManagementView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var students: [Student] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingAddStudent = false
    @State private var editingStudent: Student?
    @State private var studentToDelete: Student?
    @State private var showingDeleteConfirm = false
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading students…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if students.isEmpty {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.badge.plus",
                        description: Text("Tap + to add the first student.")
                    )
                } else {
                    List {
                        ForEach(students) { student in
                            StudentRow(student: student)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        studentToDelete = student
                                        showingDeleteConfirm = true
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button {
                                        editingStudent = student
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Students")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showingAddStudent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingAddStudent) {
                StudentFormView(mode: .create) { Task { await load() } }
            }
            .sheet(item: $editingStudent) { student in
                StudentFormView(mode: .edit(student)) { Task { await load() } }
            }
            .sheet(isPresented: $showingImport) {
                StudentImportView()
            }
            .confirmationDialog(
                "Remove \(studentToDelete?.fullName ?? "student")?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let s = studentToDelete {
                        Task { await deactivate(s) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The student will be hidden from all class rosters. This can be undone in the database.")
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            students = try await AttendanceService.shared.fetchAllStudents()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deactivate(_ student: Student) async {
        do {
            try await AttendanceService.shared.deactivateStudent(id: student.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct StudentRow: View {
    let student: Student

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(student.fullName)
                .font(.headline)
            HStack(spacing: 8) {
                if let school = student.school {
                    Text(school)
                }
                if let year = student.yearOfStudy {
                    Text("·")
                    Text(year)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

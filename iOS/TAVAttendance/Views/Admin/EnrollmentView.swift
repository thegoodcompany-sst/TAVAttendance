import SwiftUI

struct EnrollmentView: View {
    let tavClass: TAVClass

    @Environment(\.dismiss) private var dismiss

    @State private var allStudents: [Student] = []
    @State private var enrollments: [Enrollment] = []
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var error: String?
    @State private var showingAddSheet = false
    @State private var searchText = ""

    private var enrolledIds: Set<UUID> {
        Set(enrollments.map(\.studentId))
    }

    private var enrolledStudents: [Student] {
        allStudents.filter { enrolledIds.contains($0.id) }
    }

    private var unenrolledStudents: [Student] {
        let filtered = allStudents.filter { !enrolledIds.contains($0.id) }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    enrolledList
                }
            }
            .navigationTitle("Students — \(tavClass.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        searchText = ""
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(unenrolledStudents.isEmpty && searchText.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addStudentsSheet
            }
            .task { await load() }
        }
    }

    // MARK: - Enrolled list

    private var enrolledList: some View {
        List {
            if enrolledStudents.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No students enrolled yet.")
                            .foregroundStyle(.secondary)
                        Text("Tap + to add students to this class.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section("\(enrolledStudents.count) enrolled") {
                    ForEach(enrolledStudents) { student in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(student.fullName).font(.headline)
                                if let school = student.school {
                                    Text(school).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await unenroll(student) }
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    // MARK: - Add students sheet

    private var addStudentsSheet: some View {
        NavigationStack {
            List {
                if unenrolledStudents.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "All students enrolled" : "No results",
                        systemImage: "checkmark.circle",
                        description: Text(searchText.isEmpty
                            ? "Every student is already in this class."
                            : "Try a different name.")
                    )
                } else {
                    ForEach(unenrolledStudents) { student in
                        Button {
                            Task { await enroll(student) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.fullName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 4) {
                                        if let school = student.school { Text(school) }
                                        if let year = student.yearOfStudy {
                                            Text("·")
                                            Text(year)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search students")
            .navigationTitle("Add to \(tavClass.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingAddSheet = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        error = nil
        do {
            async let students = AttendanceService.shared.fetchAllStudents()
            async let enrolls  = AttendanceService.shared.fetchEnrollments(classId: tavClass.id)
            (allStudents, enrollments) = try await (students, enrolls)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func enroll(_ student: Student) async {
        do {
            try await AttendanceService.shared.enrollStudent(studentId: student.id, classId: tavClass.id)
            // Refresh enrollments so the student moves to the enrolled list
            enrollments = try await AttendanceService.shared.fetchEnrollments(classId: tavClass.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func unenroll(_ student: Student) async {
        do {
            try await AttendanceService.shared.unenrollStudent(studentId: student.id, classId: tavClass.id)
            enrollments = try await AttendanceService.shared.fetchEnrollments(classId: tavClass.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

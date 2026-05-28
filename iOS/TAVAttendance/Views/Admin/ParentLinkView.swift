import SwiftUI

struct ParentLinkView: View {
    @State private var parents: [Profile] = []
    @State private var students: [Student] = []
    @State private var selectedParent: Profile? = nil
    @State private var linkedStudentIds: Set<UUID> = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text("Parent accounts are created via the Supabase Dashboard. Use this screen to link them to their children.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("Select Parent") {
                            if parents.isEmpty {
                                Text("No parent accounts found.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(parents) { parent in
                                    HStack {
                                        Text(parent.fullName)
                                        Spacer()
                                        if selectedParent?.id == parent.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Task { await selectParent(parent) }
                                    }
                                }
                            }
                        }

                        if selectedParent != nil {
                            Section("Linked Students") {
                                if students.isEmpty {
                                    Text("No students found.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(students) { student in
                                        HStack {
                                            Text(student.fullName)
                                            Spacer()
                                            Image(systemName: linkedStudentIds.contains(student.id)
                                                  ? "checkmark.circle.fill"
                                                  : "circle")
                                                .foregroundStyle(linkedStudentIds.contains(student.id)
                                                                 ? Color.blue
                                                                 : Color.secondary)
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            Task { await toggleLink(student) }
                                        }
                                    }
                                }
                            }
                        }

                        if let err = errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red).font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Parent Links")
            .task { await load() }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let p = AttendanceService.shared.fetchParents()
            async let s = AttendanceService.shared.fetchAllStudents()
            (parents, students) = try await (p, s)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectParent(_ parent: Profile) async {
        selectedParent = parent
        linkedStudentIds = []
        errorMessage = nil
        do {
            let ids = try await AttendanceService.shared.fetchParentLinks(parentId: parent.id)
            linkedStudentIds = Set(ids)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLink(_ student: Student) async {
        guard let parent = selectedParent else { return }
        errorMessage = nil
        do {
            if linkedStudentIds.contains(student.id) {
                try await AttendanceService.shared.unlinkParentFromStudent(
                    parentId: parent.id, studentId: student.id)
                linkedStudentIds.remove(student.id)
            } else {
                try await AttendanceService.shared.linkParentToStudent(
                    parentId: parent.id, studentId: student.id)
                linkedStudentIds.insert(student.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

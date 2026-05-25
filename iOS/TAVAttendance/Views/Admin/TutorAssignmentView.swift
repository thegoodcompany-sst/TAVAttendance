import SwiftUI

struct TutorAssignmentView: View {
    let tavClass: TAVClass

    @Environment(\.dismiss) private var dismiss

    @State private var allTutors: [Profile] = []
    @State private var assignments: [TutorAssignment] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingAddSheet = false
    @State private var searchText = ""

    private var assignedIds: Set<UUID> {
        Set(assignments.map(\.tutorId))
    }

    private var assignedTutors: [Profile] {
        allTutors.filter { assignedIds.contains($0.id) }
    }

    private var unassignedTutors: [Profile] {
        let unassigned = allTutors.filter { !assignedIds.contains($0.id) }
        if searchText.isEmpty { return unassigned }
        return unassigned.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    assignedList
                }
            }
            .navigationTitle("Teachers — \(tavClass.name)")
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
                    .disabled(unassignedTutors.isEmpty && searchText.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addTutorSheet
            }
            .task { await load() }
        }
    }

    // MARK: - Assigned list

    private var assignedList: some View {
        List {
            if assignedTutors.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No teachers assigned yet.")
                            .foregroundStyle(.secondary)
                        Text("Tap + to assign a teacher to this class.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section("\(assignedTutors.count) assigned") {
                    ForEach(assignedTutors) { tutor in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tutor.fullName).font(.headline)
                                if let phone = tutor.phone {
                                    Text(phone).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await unassign(tutor) }
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

    // MARK: - Add tutor sheet

    private var addTutorSheet: some View {
        NavigationStack {
            List {
                if allTutors.isEmpty {
                    ContentUnavailableView(
                        "No Teachers",
                        systemImage: "person.slash",
                        description: Text("No tutor accounts exist yet. Invite teachers first.")
                    )
                } else if unassignedTutors.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "All Teachers Assigned" : "No Results",
                        systemImage: "checkmark.circle",
                        description: Text(searchText.isEmpty
                            ? "Every teacher is already assigned to this class."
                            : "Try a different name.")
                    )
                } else {
                    ForEach(unassignedTutors) { tutor in
                        Button {
                            Task { await assign(tutor) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tutor.fullName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let phone = tutor.phone {
                                        Text(phone).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search teachers")
            .navigationTitle("Add Teacher")
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
            async let tutors      = AttendanceService.shared.fetchTutors()
            async let currentAssignments = AttendanceService.shared.fetchTutorAssignments(classId: tavClass.id)
            (allTutors, assignments) = try await (tutors, currentAssignments)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func assign(_ tutor: Profile) async {
        do {
            try await AttendanceService.shared.assignTutor(tutorId: tutor.id, classId: tavClass.id)
            assignments = try await AttendanceService.shared.fetchTutorAssignments(classId: tavClass.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func unassign(_ tutor: Profile) async {
        do {
            try await AttendanceService.shared.unassignTutor(tutorId: tutor.id, classId: tavClass.id)
            assignments = try await AttendanceService.shared.fetchTutorAssignments(classId: tavClass.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

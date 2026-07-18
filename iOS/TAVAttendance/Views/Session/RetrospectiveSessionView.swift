import SwiftUI

struct PastSessionFormView: View {
    let tavClass: TAVClass
    let sessions: [Session]
    let tutors: [Profile]
    let onCreated: (Session) -> Void
    let onExisting: (Session) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var featureFlags: FeatureFlagStore
    @StateObject private var network = NetworkMonitor()
    @State private var date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var topic = ""
    @State private var notes = ""
    @State private var subTutorId: UUID?
    @State private var isSaving = false
    @State private var error: AppError?

    private var latestDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                if !network.isConnected {
                    Label("Connect to the internet to create a past session.", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                }

                Section("Session") {
                    DatePicker("Date", selection: $date, in: ...latestDate, displayedComponents: .date)
                    TextField("Topic (optional)", text: $topic)
                    if featureFlags.isEnabled(.sessionNotes) {
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }

                Section("Substitute") {
                    Picker("Teacher", selection: $subTutorId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(tutors) { tutor in
                            Text(tutor.fullName).tag(tutor.id as UUID?)
                        }
                    }
                }
            }
            .navigationTitle("Add Past Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Create") { Task { await create() } }
                        .disabled(isSaving || !network.isConnected)
                }
            }
            .errorAlert(error: $error)
        }
    }

    private func create() async {
        guard RetrospectiveSessionRules.isPastDate(date) else {
            error = AppError("Choose a date before today.")
            return
        }
        if let existing = RetrospectiveSessionRules.existingSession(on: date, in: sessions) {
            dismiss()
            onExisting(existing)
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await AttendanceService.shared.createRetrospectiveSession(
                classId: tavClass.id,
                sessionDate: AttendanceService.ymdFormatter.string(from: date),
                topic: topic, notes: featureFlags.isEnabled(.sessionNotes) ? notes : nil,
                subTutorId: subTutorId)
            Analytics.shared.track(.ops, name: "retrospective_session_created",
                                   properties: ["screen": .string("session_list")])
            dismiss()
            onCreated(created)
        } catch {
            self.error = AppError("Could not create the past session.", underlyingError: error)
        }
    }
}

struct HistoricalSessionEditorView: View {
    @State private var session: Session
    let tavClass: TAVClass
    let onUpdated: (Session) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var featureFlags: FeatureFlagStore
    @StateObject private var network = NetworkMonitor()
    @State private var roster: [RosterEntry] = []
    @State private var students: [Student] = []
    @State private var tutors: [Profile] = []
    @State private var topic: String
    @State private var notes: String
    @State private var subTutorId: UUID?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showingStudentPicker = false
    @State private var error: AppError?

    init(session: Session, tavClass: TAVClass, onUpdated: @escaping (Session) -> Void) {
        _session = State(initialValue: session)
        self.tavClass = tavClass
        self.onUpdated = onUpdated
        _topic = State(initialValue: session.topic ?? "")
        _notes = State(initialValue: session.notes ?? "")
        _subTutorId = State(initialValue: session.subTutorId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading editor…")
                } else {
                    List {
                        if !network.isConnected {
                            Label("Historical changes are online only.", systemImage: "wifi.slash")
                                .foregroundStyle(.orange)
                        }

                        Section("Details") {
                            LabeledContent("Class", value: tavClass.name)
                            LabeledContent("Date", value: session.sessionDate)
                            TextField("Topic (optional)", text: $topic)
                            if featureFlags.isEnabled(.sessionNotes) {
                                TextField("Notes (optional)", text: $notes, axis: .vertical)
                                    .lineLimit(3...6)
                            }
                            Picker("Substitute", selection: $subTutorId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(tutors) { tutor in
                                    Text(tutor.fullName).tag(tutor.id as UUID?)
                                }
                            }
                            Button(isSaving ? "Saving…" : "Save Details") {
                                Task { await saveDetails() }
                            }
                            .disabled(isSaving || !network.isConnected)
                        }

                        Section {
                            ForEach(roster) { entry in
                                HStack {
                                    Text(entry.fullName)
                                    Spacer()
                                    Picker("Status", selection: statusBinding(for: entry)) {
                                        Text("Unmarked").tag(nil as AttendanceStatus?)
                                        ForEach(AttendanceStatus.allCases, id: \.self) { status in
                                            Text(statusLabel(status)).tag(status as AttendanceStatus?)
                                        }
                                    }
                                    .labelsHidden()
                                    .disabled(!network.isConnected)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Attendance")
                                Spacer()
                                Button("Add Student") { showingStudentPicker = true }
                                    .textCase(nil)
                                    .disabled(!network.isConnected)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingStudentPicker) {
                RetrospectiveStudentPicker(
                    students: availableStudents,
                    onSelect: { student, status in
                        showingStudentPicker = false
                        Task { await mark(studentId: student.id, status: status, isAdded: true) }
                    })
            }
            .errorAlert(error: $error)
        }
    }

    private var availableStudents: [Student] {
        let rosterIds = Set(roster.map(\.studentId))
        return students.filter { !rosterIds.contains($0.id) }
    }

    private func statusBinding(for entry: RosterEntry) -> Binding<AttendanceStatus?> {
        Binding(
            get: { roster.first(where: { $0.id == entry.id })?.status },
            set: { status in
                guard let status else { return }
                Task { await mark(studentId: entry.studentId, status: status, isAdded: false) }
            })
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let rosterResult = AttendanceService.shared.fetchRetrospectiveRoster(sessionId: session.id)
            async let studentResult = AttendanceService.shared.fetchAllStudents()
            async let tutorResult = AttendanceService.shared.fetchTutors()
            (roster, students, tutors) = try await (rosterResult, studentResult, tutorResult)
        } catch {
            self.error = AppError("Could not load the historical editor.", underlyingError: error)
        }
    }

    private func saveDetails() async {
        guard network.isConnected else {
            error = AppError("Historical changes require an internet connection.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            session = try await AttendanceService.shared.updateRetrospectiveSession(
                sessionId: session.id, topic: topic,
                notes: featureFlags.isEnabled(.sessionNotes) ? notes : nil,
                subTutorId: subTutorId)
            onUpdated(session)
            Analytics.shared.track(.ops, name: "retrospective_session_updated",
                                   properties: ["screen": .string("historical_editor")])
        } catch {
            self.error = AppError("Could not save session details.", underlyingError: error)
        }
    }

    private func mark(studentId: UUID, status: AttendanceStatus, isAdded: Bool) async {
        guard network.isConnected else {
            error = AppError("Historical attendance changes require an internet connection.")
            return
        }
        do {
            try await AttendanceService.shared.markRetrospectiveAttendance(
                sessionId: session.id, studentId: studentId, status: status)
            roster = try await AttendanceService.shared.fetchRetrospectiveRoster(sessionId: session.id)
            Analytics.shared.track(.ops,
                name: isAdded ? "retrospective_student_added" : "retrospective_attendance_corrected",
                properties: ["screen": .string("historical_editor"), "status": .string(status.rawValue)])
        } catch {
            self.error = AppError("Could not update historical attendance.", underlyingError: error)
        }
    }

    private func statusLabel(_ status: AttendanceStatus) -> String {
        switch status {
        case .present: return "Present"
        case .late: return "Late"
        case .absent: return "Absent"
        case .excused: return "Excused"
        }
    }
}

private struct RetrospectiveStudentPicker: View {
    let students: [Student]
    let onSelect: (Student, AttendanceStatus) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(students) { student in
                Menu {
                    ForEach(AttendanceStatus.allCases, id: \.self) { status in
                        Button(statusLabel(status)) { onSelect(student, status) }
                    }
                } label: {
                    HStack {
                        Text(student.fullName).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                    .contentShape(Rectangle())
                }
            }
            .overlay {
                if students.isEmpty {
                    ContentUnavailableView("No Students to Add", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .navigationTitle("Add Student")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func statusLabel(_ status: AttendanceStatus) -> String {
        status.rawValue.capitalized
    }
}

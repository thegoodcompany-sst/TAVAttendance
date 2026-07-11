import SwiftUI

/// Tutor-facing Students tab: read-only student list with per-subject grade entry.
/// RLS limits the list to students enrolled in the tutor's assigned classes, and the
/// subjects offered are the (normalized) subjects of those classes.
struct StudentResultsView: View {
    @State private var students: [Student] = []
    @State private var results: [UUID: [ResultSlipSubject: String]] = [:]
    @State private var subjects: [ResultSlipSubject] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedStudent: Student?

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
                        systemImage: "person.3",
                        description: Text("Students enrolled in your classes will appear here.")
                    )
                } else {
                    List(students) { student in
                        Button {
                            selectedStudent = student
                        } label: {
                            ResultRow(student: student, grades: results[student.id] ?? [:])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Students")
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $selectedStudent) { student in
                ResultEntrySheet(
                    student: student,
                    subjects: subjects,
                    grades: results[student.id] ?? [:]
                ) { subject, grade in
                    results[student.id, default: [:]][subject] = grade
                }
            }
        }
    }

    private func load() async {
        error = nil
        do {
            async let studentsTask = AttendanceService.shared.fetchAllStudents()
            async let classesTask = AttendanceService.shared.fetchMyClasses()
            async let resultsTask = AttendanceService.shared.fetchStudentResults()
            students = try await studentsTask
            subjects = Array(Set(try await classesTask.compactMap { ResultSlipSubject(normalizing: $0.subject) }))
                .sorted { $0.rawValue < $1.rawValue }
            results = try await resultsTask.reduce(into: [:]) { dict, r in
                guard let subject = ResultSlipSubject(rawValue: r.subject) else { return }
                dict[r.studentId, default: [:]][subject] = r.grade
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ResultRow: View {
    let student: Student
    let grades: [ResultSlipSubject: String]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.fullName)
                    .font(.headline)
                HStack(spacing: 8) {
                    if let school = student.school { Text(school) }
                    if let year = student.yearOfStudy {
                        if student.school != nil { Text("·") }
                        Text(year)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !grades.isEmpty {
                Text(grades.keys.sorted { $0.rawValue < $1.rawValue }
                    .map { "\($0.rawValue): \(grades[$0]!)" }
                    .joined(separator: "  "))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct ResultEntrySheet: View {
    let student: Student
    let subjects: [ResultSlipSubject]
    let grades: [ResultSlipSubject: String]
    var onChange: (ResultSlipSubject, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if subjects.isEmpty {
                    Text("None of your assigned classes has a subject set, so there is nothing to grade. Ask an admin to set the class subject.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(subjects) { subject in
                            GradeRow(
                                student: student,
                                subject: subject,
                                initialGrade: grades[subject],
                                onChange: onChange,
                                onError: { error = $0 }
                            )
                        }
                    } header: {
                        Text("Latest Grades")
                    } footer: {
                        if let error {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(student.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct GradeRow: View {
    let student: Student
    let subject: ResultSlipSubject
    let onChange: (ResultSlipSubject, String?) -> Void
    let onError: (String) -> Void

    @State private var grade: String
    @State private var isReverting = false

    init(student: Student, subject: ResultSlipSubject, initialGrade: String?,
         onChange: @escaping (ResultSlipSubject, String?) -> Void,
         onError: @escaping (String) -> Void) {
        self.student = student
        self.subject = subject
        self.onChange = onChange
        self.onError = onError
        _grade = State(initialValue: initialGrade ?? "")
    }

    var body: some View {
        Picker(subject.displayName, selection: $grade) {
            Text("Not graded").tag("")
            // Primary (PSLE AL) vs secondary (O-Level) band first, based on
            // year_of_study; both offered because the field is free text.
            ForEach(orderedBands, id: \.self) { band in
                Section(band == GradeBands.primary ? "Primary (AL)" : "Secondary (O-Level)") {
                    ForEach(band, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .onChange(of: grade) { oldValue, newValue in
            if isReverting { isReverting = false; return }
            Task { await save(oldValue: oldValue, newValue: newValue) }
        }
    }

    private var orderedBands: [[String]] {
        student.isPrimaryLevel == true
            ? [GradeBands.primary, GradeBands.secondary]
            : [GradeBands.secondary, GradeBands.primary]
    }

    private func save(oldValue: String, newValue: String) async {
        do {
            if newValue.isEmpty {
                try await AttendanceService.shared.deleteStudentResult(
                    studentId: student.id, subject: subject)
                onChange(subject, nil)
            } else {
                try await AttendanceService.shared.upsertStudentResult(
                    studentId: student.id, subject: subject, grade: newValue)
                onChange(subject, newValue)
            }
        } catch {
            onError("Couldn't save \(subject.displayName) grade: \(error.localizedDescription)")
            isReverting = true
            grade = oldValue
        }
    }
}

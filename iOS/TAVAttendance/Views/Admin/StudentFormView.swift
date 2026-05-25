import SwiftUI

struct StudentFormView: View {
    enum Mode {
        case create
        case edit(Student)
    }

    let mode: Mode
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var school = ""
    @State private var yearOfStudy = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onSave: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let student) = mode {
            _fullName    = State(initialValue: student.fullName)
            _school      = State(initialValue: student.school ?? "")
            _yearOfStudy = State(initialValue: student.yearOfStudy ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Student Details") {
                    TextField("Full name *", text: $fullName)
                    TextField("School", text: $school)
                    TextField("Year of study (e.g. Sec 2, JC1)", text: $yearOfStudy)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Student" : "New Student")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(fullName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let insert = StudentInsert(
            fullName:    fullName.trimmingCharacters(in: .whitespaces),
            school:      school.isEmpty ? nil : school,
            yearOfStudy: yearOfStudy.isEmpty ? nil : yearOfStudy
        )
        do {
            if case .edit(let student) = mode {
                try await AttendanceService.shared.updateStudent(id: student.id, insert)
            } else {
                _ = try await AttendanceService.shared.createStudent(insert)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

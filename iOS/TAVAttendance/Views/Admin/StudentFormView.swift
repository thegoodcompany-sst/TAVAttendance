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

    // PDPA consent attestation (create mode only)
    @State private var consentObtained = false
    @State private var noticeVersion: String?

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

                if !isEditing {
                    Section {
                        Toggle(isOn: $consentObtained) {
                            Text("Parent/guardian consent obtained for collection of this child's data")
                        }
                    } footer: {
                        Text("Required (PDPA). You must confirm parental/guardian consent before adding a student. A consent record is logged on save.")
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Student" : "New Student")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !isEditing {
                    noticeVersion = try? await AttendanceService.shared.fetchPrivacyNotice()?.version
                }
            }
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
                        .disabled(saveDisabled)
                    }
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var saveDisabled: Bool {
        if isSaving { return true }
        if fullName.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        // Block creation until parental consent is attested (PDPA).
        if !isEditing && !consentObtained { return true }
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
        // PDPA: hard guard — never create a student without attested consent.
        if !isEditing && !consentObtained {
            errorMessage = "Parental/guardian consent must be confirmed before adding a student."
            isSaving = false
            return
        }
        do {
            if case .edit(let student) = mode {
                try await AttendanceService.shared.updateStudent(id: student.id, insert)
            } else {
                let created = try await AttendanceService.shared.createStudent(insert)
                // Append the consent ledger row. If this fails the student already exists;
                // surface the error so the admin can retry the consent step.
                try await AttendanceService.shared.recordConsent(
                    studentId: created.id, noticeVersion: noticeVersion)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

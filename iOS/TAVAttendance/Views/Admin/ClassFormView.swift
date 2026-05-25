import SwiftUI

struct ClassFormView: View {
    enum Mode {
        case create
        case edit(TAVClass)
    }

    let mode: Mode
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var subject = ""
    @State private var level = ""
    @State private var scheduleDay = ""
    @State private var scheduleTime = ""
    @State private var durationMinutes = 90
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let days = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

    init(mode: Mode, onSave: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let cls) = mode {
            _name           = State(initialValue: cls.name)
            _subject        = State(initialValue: cls.subject ?? "")
            _level          = State(initialValue: cls.level ?? "")
            _scheduleDay    = State(initialValue: cls.scheduleDay ?? "")
            _scheduleTime   = State(initialValue: cls.scheduleTime ?? "")
            _durationMinutes = State(initialValue: cls.durationMinutes)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class Details") {
                    TextField("Class name *", text: $name)
                    TextField("Subject (e.g. Mathematics)", text: $subject)
                    TextField("Level (e.g. Sec 2)", text: $level)
                }

                Section("Schedule") {
                    Picker("Day", selection: $scheduleDay) {
                        Text("—").tag("")
                        ForEach(days, id: \.self) { day in
                            Text(day).tag(day)
                        }
                    }
                    TextField("Time (e.g. 19:00)", text: $scheduleTime)
                        .keyboardType(.numbersAndPunctuation)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 30...240, step: 15)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Class" : "New Class")
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        let insert = ClassInsert(
            name:            name.trimmingCharacters(in: .whitespaces),
            subject:         subject.isEmpty ? nil : subject,
            level:           level.isEmpty ? nil : level,
            scheduleDay:     scheduleDay.isEmpty ? nil : scheduleDay,
            scheduleTime:    scheduleTime.isEmpty ? nil : scheduleTime,
            durationMinutes: durationMinutes,
            isActive:        true
        )
        do {
            if case .edit(let cls) = mode {
                try await AttendanceService.shared.updateClass(id: cls.id, insert)
            } else {
                _ = try await AttendanceService.shared.createClass(insert)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

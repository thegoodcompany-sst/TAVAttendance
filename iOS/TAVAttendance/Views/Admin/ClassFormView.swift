import SwiftUI

private enum RecurrenceMode: Equatable {
    case none
    case weekly
    case custom
}

private let weekdays = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
private let dayAbbrev: [String: String] = [
    "Monday": "MO", "Tuesday": "TU", "Wednesday": "WE",
    "Thursday": "TH", "Friday": "FR", "Saturday": "SA", "Sunday": "SU"
]
private let abbrevToDay = Dictionary(uniqueKeysWithValues: dayAbbrev.map { ($1, $0) })

struct ClassFormView: View {
    enum Mode {
        case create
        case edit(TAVClass)
    }

    let mode: Mode
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var subject: ResultSlipSubject?
    @State private var level = ""
    @State private var scheduleDay = ""
    @State private var scheduleTime = ""
    @State private var durationMinutes = 90
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Recurrence
    @State private var recurrenceMode: RecurrenceMode = .none
    @State private var selectedDays: Set<String> = []
    @State private var recurrenceEndDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var hasEndDate = false

    init(mode: Mode, onSave: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let cls) = mode {
            _name           = State(initialValue: cls.name)
            _subject        = State(initialValue: ResultSlipSubject(normalizing: cls.subject))
            _level          = State(initialValue: cls.level ?? "")
            _scheduleDay    = State(initialValue: cls.scheduleDay ?? "")
            _scheduleTime   = State(initialValue: cls.scheduleTime ?? "")
            _durationMinutes = State(initialValue: cls.durationMinutes)

            // Parse recurrence
            if let rule = cls.recurrenceRule {
                let parts = rule.split(separator: ";").map(String.init)
                var byDays: [String] = []
                for part in parts {
                    if part.hasPrefix("BYDAY=") {
                        byDays = part.dropFirst(6).split(separator: ",").map(String.init)
                    }
                }
                if byDays.count > 1 {
                    _recurrenceMode = State(initialValue: .custom)
                    _selectedDays = State(initialValue: Set(byDays.compactMap { abbrevToDay[$0] }))
                } else if !byDays.isEmpty {
                    _recurrenceMode = State(initialValue: .weekly)
                }
            }
            if let endDateStr = cls.recurrenceEndDate {
                let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                if let date = fmt.date(from: endDateStr) {
                    _recurrenceEndDate = State(initialValue: date)
                    _hasEndDate = State(initialValue: true)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class Details") {
                    TextField("Class name *", text: $name)
                    Picker("Subject", selection: $subject) {
                        Text("—").tag(nil as ResultSlipSubject?)
                        ForEach(ResultSlipSubject.allCases) { s in
                            Text(s.displayName).tag(s as ResultSlipSubject?)
                        }
                    }
                    TextField("Level (e.g. Sec 2)", text: $level)
                }

                Section("Schedule") {
                    Picker("Day", selection: $scheduleDay) {
                        Text("—").tag("")
                        ForEach(weekdays, id: \.self) { day in
                            Text(day).tag(day)
                        }
                    }
                    TextField("Time (e.g. 19:00)", text: $scheduleTime)
                        .keyboardType(.numbersAndPunctuation)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 30...240, step: 15)
                }

                Section("Recurrence") {
                    Picker("Repeats", selection: $recurrenceMode) {
                        Text("Never").tag(RecurrenceMode.none)
                        Text("Weekly").tag(RecurrenceMode.weekly)
                        Text("Custom days").tag(RecurrenceMode.custom)
                    }
                    .pickerStyle(.segmented)

                    if recurrenceMode == .custom {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Days of Week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(weekdays, id: \.self) { day in
                                    let short = String(day.prefix(2))
                                    let isSelected = selectedDays.contains(day)
                                    Button {
                                        if isSelected {
                                            selectedDays.remove(day)
                                        } else {
                                            selectedDays.insert(day)
                                        }
                                    } label: {
                                        Text(short)
                                            .font(.caption2)
                                            .frame(width: 32, height: 28)
                                            .background(isSelected ? Color.blue : Color(.systemGray5))
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if recurrenceMode != .none {
                        Toggle("Has End Date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("End Date", selection: $recurrenceEndDate, displayedComponents: .date)
                        }
                    }
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

    private func buildRRule() -> String? {
        switch recurrenceMode {
        case .none:
            return nil
        case .weekly:
            guard !scheduleDay.isEmpty, let abbrev = dayAbbrev[scheduleDay] else {
                return "FREQ=WEEKLY"
            }
            return "FREQ=WEEKLY;BYDAY=\(abbrev)"
        case .custom:
            let ordered = weekdays.filter { selectedDays.contains($0) }
            guard !ordered.isEmpty else { return "FREQ=WEEKLY" }
            let byDay = ordered.compactMap { dayAbbrev[$0] }.joined(separator: ",")
            return "FREQ=WEEKLY;BYDAY=\(byDay)"
        }
    }

    private func buildEndDate() -> String? {
        guard recurrenceMode != .none && hasEndDate else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: recurrenceEndDate)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let insert = ClassInsert(
            name:            name.trimmingCharacters(in: .whitespaces),
            subject:         subject?.rawValue,
            level:           level.isEmpty ? nil : level,
            scheduleDay:     scheduleDay.isEmpty ? nil : scheduleDay,
            scheduleTime:    scheduleTime.isEmpty ? nil : scheduleTime,
            durationMinutes: durationMinutes,
            isActive:        true,
            recurrenceRule:  buildRRule(),
            recurrenceEndDate: buildEndDate()
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

import SwiftUI
import UIKit
import PromptRouter

struct TeacherLessonsView: View {
    @ObservedObject var coordinator: TeacherPromptCoordinator
    @EnvironmentObject private var auth: AuthManager
    var body: some View {
        NavigationStack {
            List {
                if coordinator.gate.demo { Text(PromptStrings.demo).foregroundStyle(.secondary) }
                if let message = coordinator.message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                        Button(PromptStrings.retry) { Task { await coordinator.foreground() } }
                    }
                }
                if let result = coordinator.lessons {
                    Section {
                        Text("\(result.outstanding_count) \(PromptStrings.outstanding)")
                            .font(.headline).accessibilityIdentifier("teacher.outstanding")
                    }
                    Section(PromptStrings.todaysLessons) {
                        if result.lessons.isEmpty { Text(PromptStrings.empty) }
                        ForEach(result.lessons) { lesson in lessonRow(lesson) }
                    }
                    if !result.backlog.isEmpty {
                        Section(PromptStrings.backlog) {
                            ForEach(result.backlog) { lesson in lessonRow(lesson) }
                        }
                    }
                } else if coordinator.listBusy { ProgressView(PromptStrings.loading) }
                Section {
                    Text(PromptStrings.noDevices).foregroundStyle(.secondary)
                    if !coordinator.gate.demo && coordinator.gate.pushFlag {
                        Toggle(PromptStrings.enableReminders, isOn: Binding(
                            get: { coordinator.optedIn },
                            set: { value in Task { await coordinator.setOptedIn(value) } }))
                            .accessibilityIdentifier("teacher.optIn")
                    }
                }
            }
            .navigationTitle(PromptStrings.myLessons)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(PromptStrings.signOut) { Task { try? await auth.signOut() } }
                }
            }
            .refreshable { await coordinator.foreground() }
            .task(id: coordinator.unlocked) { await coordinator.loadLessons() }
        }
        .tint(.blue)
    }
    private func lessonRow(_ lesson: TeacherLessonSummary) -> some View {
        Button { coordinator.openLesson(lesson.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(lesson.class_label).font(.headline)
                Text(TeacherPromptFormat.time(lesson.scheduled_start_at) + " – " + TeacherPromptFormat.time(lesson.scheduled_end_at))
                    .foregroundStyle(.secondary)
                Text(TeacherPromptFormat.state(lesson.state)).foregroundStyle(.indigo)
                Text(lesson.accountable_teacher_label).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(PromptStrings.takeAttendance)
        .accessibilityIdentifier("teacher.lesson.\(lesson.id.uuidString.lowercased())")
    }
}

struct TeacherPromptRouteView: View {
    @ObservedObject var coordinator: TeacherPromptCoordinator
    var body: some View {
        NavigationStack {
            Group {
                if let model = coordinator.lessonModel {
                    TeacherLessonView(model: model)
                } else {
                    VStack(spacing: 20) {
                        if case .resolving = coordinator.state { ProgressView(PromptStrings.loading) }
                        else {
                            Text(coordinator.message ?? PromptStrings.unavailable)
                            Button(PromptStrings.retry) { coordinator.retry() }
                        }
                    }.padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(PromptStrings.back) { coordinator.close() }
                        .accessibilityIdentifier("teacher.back")
                }
            }
        }
        .tint(.blue)
    }
}

struct TeacherLessonView: View {
    @ObservedObject var model: TeacherLessonModel
    var body: some View {
        List {
            if let p = model.projection {
                Section {
                    Text(p.lesson.class_label).font(.title2.bold())
                    Text(TeacherPromptFormat.state(p.lesson.state)).foregroundStyle(.indigo)
                }
                if model.confirmingSnooze {
                    Section {
                        Text(PromptStrings.confirmSnooze).font(.headline)
                            .accessibilityIdentifier("teacher.snoozeConfirmation")
                        Button(PromptStrings.snoozeTen) { Task { await model.confirmSnooze() } }
                            .disabled(!model.canSnooze)
                            .accessibilityIdentifier("teacher.confirmSnooze")
                        Button(PromptStrings.cancel) { model.confirmingSnooze = false }
                    }
                }
                Section(PromptStrings.attendance) {
                    if !model.submitted {
                        Button(PromptStrings.allPresent) { Task { await model.allPresent() } }
                            .disabled(!model.canEdit || model.notesDirty)
                            .accessibilityIdentifier("teacher.allPresent")
                        Text(PromptStrings.allPresentHelp).font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.reviewingAllPresent {
                        Text(PromptStrings.allPresentReview).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("teacher.allPresentReview")
                    }
                    ForEach(model.roster) { student in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(student.display_name).font(.headline)
                            HStack {
                                Text(student.status?.label ?? PromptStrings.notMarked)
                                    .foregroundStyle(student.status == .present ? Color.teal : Color.indigo)
                                Spacer()
                                Menu {
                                    ForEach(TeacherAttendanceStatus.allCases, id: \.self) { status in
                                        Button(status.label) {
                                            Task { await model.mark(student, status: status,
                                                informed: status == .absent ? student.absence_informed : nil) }
                                        }
                                    }
                                    Button(PromptStrings.clear) { Task { await model.mark(student, status: nil) } }
                                } label: {
                                    Label(PromptStrings.attendance, systemImage: "pencil.circle")
                                        .frame(minHeight: 44)
                                }
                                .disabled(!model.canEdit)
                                .accessibilityLabel(student.display_name + ", " + PromptStrings.attendance)
                                .accessibilityValue(student.status?.label ?? PromptStrings.notMarked)
                                .accessibilityIdentifier("teacher.status.\(student.id.uuidString.lowercased())")
                            }
                            if student.status == .absent {
                                Toggle(PromptStrings.informed, isOn: Binding(
                                    get: { student.absence_informed == true },
                                    set: { value in Task { await model.mark(student, status: .absent, informed: value) } }))
                                    .disabled(!model.canEdit).tint(.teal)
                                    .accessibilityLabel(student.display_name + ", " + PromptStrings.informed)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if !model.submitted {
                    Section {
                        Button(model.reviewingAllPresent ? PromptStrings.confirmAndSubmit : PromptStrings.submit) { Task { await model.submit() } }
                            .disabled(!model.canSubmit)
                            .accessibilityIdentifier("teacher.submit")
                        Button(PromptStrings.snoozeTen) { model.confirmingSnooze = true }
                            .disabled(!model.canSnooze)
                            .accessibilityIdentifier("teacher.snooze")
                        if !p.lesson.can_edit { Text(PromptStrings.readOnly).foregroundStyle(.secondary) }
                        if model.busy { ProgressView(PromptStrings.loading) }
                    }
                }
                Section(PromptStrings.notes + " · " + PromptStrings.optional) {
                    Text(PromptStrings.notesHelp).font(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $model.notes)
                        .frame(minHeight: 100)
                        .disabled(!model.canEdit)
                        .accessibilityLabel(PromptStrings.notes)
                        .accessibilityIdentifier("teacher.notes")
                    Text("\(model.notes.unicodeScalars.count)/1000").font(.caption).foregroundStyle(.secondary)
                    if !model.submitted {
                        Button(PromptStrings.saveNotes) { Task { await model.saveNotes() } }
                            .disabled(!model.canEdit || !model.notesDirty || model.notes.unicodeScalars.count > 1000)
                    }
                }
            }
        }
        .accessibilityIdentifier("teacher.attendanceList")
        .safeAreaInset(edge: .top, spacing: 0) {
            // Outside the lazy List: outcomes and errors remain visible at any offset.
            if model.submitted || model.message != nil {
                statusBanner
            }
        }
        .interactiveDismissDisabled(model.preventsInteractiveDismissal)
        .onChange(of: model.message) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        .onChange(of: model.submitted) { _, submitted in
            if submitted { UIAccessibility.post(notification: .announcement, argument: PromptStrings.done) }
        }
        .navigationTitle(PromptStrings.attendance)
        .navigationBarTitleDisplayMode(.inline)
        .tint(.blue)
    }

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.submitted {
                // Identify the actual text, never a Label's decorative SF Symbol.
                Text(PromptStrings.done)
                    .font(.title2).foregroundStyle(.teal)
                    .accessibilityIdentifier("teacher.submitted")
                Text(PromptStrings.doneHelp).foregroundStyle(.secondary)
            }
            if let message = model.message, !model.submitted || message != PromptStrings.snoozed {
                Text(message).foregroundStyle(.secondary)
                    .accessibilityIdentifier(message == PromptStrings.snoozed ? "teacher.snoozed" : "teacher.message")
                if model.projection != nil && message != PromptStrings.snoozed {
                    Button(PromptStrings.retry) { Task { await model.retry() } }
                        .disabled(model.busy)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}

enum TeacherPromptFormat {
    static func state(_ value: String) -> String {
        switch value {
        case "scheduled": return PromptStrings.scheduled
        case "in_progress": return PromptStrings.inProgress
        case "awaiting_attendance": return PromptStrings.awaitingAttendance
        case "overdue": return PromptStrings.overdue
        case "submitted": return PromptStrings.submitted
        case "cancelled": return PromptStrings.cancelled
        default: return PromptStrings.unavailable
        }
    }
    static func time(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: value) }
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_SG")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Singapore")
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

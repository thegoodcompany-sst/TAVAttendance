import SwiftUI

/// Admin PDPA controls for one student: consent status + withdraw, subject-access
/// export, and erase / anonymise. Reached from StudentManagementView.
struct StudentPrivacyView: View {
    let student: Student
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var consent: [ConsentRecord] = []
    @State private var noticeVersion: String?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var error: AppError?
    @State private var statusMessage: String?

    @State private var exportURL: URL?
    @State private var showShare = false

    @State private var showWithdrawConfirm = false
    @State private var showAnonymiseConfirm = false
    @State private var showEraseConfirm = false

    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    private var dataCollectionConsent: ConsentRecord? {
        consent.first { $0.consentType == "data_collection" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        consentSection
                        accessSection
                        retentionSection
                        if let statusMessage {
                            Section { Text(statusMessage).foregroundStyle(.green).font(.footnote) }
                        }
                    }
                }
            }
            .navigationTitle("Privacy — \(student.fullName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(isWorking)
                }
            }
            .task { await load() }
            .errorAlert(error: $error)
            .sheet(isPresented: $showShare) {
                if let exportURL { ShareLink(item: exportURL) }
            }
            .confirmationDialog("Withdraw consent?", isPresented: $showWithdrawConfirm, titleVisibility: .visible) {
                Button("Withdraw consent", role: .destructive) { Task { await withdraw() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Records that consent for this child's data has been withdrawn. The centre should stop using the data except where legally required to retain it.")
            }
            .confirmationDialog("Anonymise student?", isPresented: $showAnonymiseConfirm, titleVisibility: .visible) {
                Button("Anonymise", role: .destructive) { Task { await anonymise() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Redacts this child's personal data but keeps anonymous attendance statistics. This cannot be undone.")
            }
            .confirmationDialog("Erase student?", isPresented: $showEraseConfirm, titleVisibility: .visible) {
                Button("Erase permanently", role: .destructive) { Task { await erase() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently deletes ALL data for this child, including attendance and audit snapshots. Use only for a confirmed erasure request. This cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var consentSection: some View {
        Section("Consent") {
            if let c = dataCollectionConsent {
                LabeledContent("Data collection") {
                    Text(c.status == .granted ? "Granted" : "Withdrawn")
                        .foregroundStyle(c.status == .granted ? .green : .red)
                }
                if let m = methodLabel(c.method) {
                    LabeledContent("Method", value: m)
                }
                if let v = c.noticeVersion {
                    LabeledContent("Notice version", value: v)
                }
                if let d = c.createdAt {
                    LabeledContent("Recorded", value: dateFmt.string(from: d))
                }
                if c.status == .granted {
                    Button(role: .destructive) {
                        showWithdrawConfirm = true
                    } label: {
                        Label("Withdraw Consent", systemImage: "hand.raised.slash")
                    }
                    .disabled(isWorking)
                }
            } else {
                Text("No consent record on file.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessSection: some View {
        Section {
            Button {
                Task { await export() }
            } label: {
                Label("Export This Student's Data", systemImage: "square.and.arrow.up")
            }
            .disabled(isWorking)
        } header: {
            Text("Subject Access")
        } footer: {
            Text("Generates a JSON bundle of all personal data held about this student (PDPA s21). The disclosure is logged.")
        }
    }

    private var retentionSection: some View {
        Section {
            Button(role: .destructive) {
                showAnonymiseConfirm = true
            } label: {
                Label("Anonymise Student", systemImage: "eye.slash")
            }
            .disabled(isWorking)

            Button(role: .destructive) {
                showEraseConfirm = true
            } label: {
                Label("Erase Student", systemImage: "trash")
            }
            .disabled(isWorking)
        } header: {
            Text("Retention & Erasure")
        } footer: {
            Text("Anonymise keeps anonymous attendance stats; Erase removes everything. Both are irreversible.")
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let consentFetch = AttendanceService.shared.fetchCurrentConsent(studentId: student.id)
            async let noticeFetch = AttendanceService.shared.fetchPrivacyNotice()
            consent = try await consentFetch
            noticeVersion = try await noticeFetch?.version
        } catch {
            self.error = AppError("Could not load consent records.", underlyingError: error)
        }
    }

    private func withdraw() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AttendanceService.shared.withdrawConsent(
                studentId: student.id, noticeVersion: noticeVersion)
            statusMessage = "Consent withdrawn."
            await load()
            onChanged()
        } catch {
            self.error = AppError("Could not withdraw consent.", underlyingError: error)
        }
    }

    private func export() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await AttendanceService.shared.exportStudentPersonalData(id: student.id)
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let fileName = "pdpa-export-\(student.id.uuidString)-\(fmt.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            // Pretty-print if it parses as JSON; otherwise write the raw bytes.
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                        options: [.prettyPrinted, .sortedKeys]) {
                try pretty.write(to: url)
            } else {
                try data.write(to: url)
            }
            exportURL = url
            showShare = true
        } catch {
            self.error = AppError("Could not export student data.", underlyingError: error)
        }
    }

    private func anonymise() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AttendanceService.shared.anonymiseStudent(id: student.id)
            onChanged()
            dismiss()
        } catch {
            self.error = AppError("Could not anonymise student.", underlyingError: error)
        }
    }

    private func erase() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AttendanceService.shared.eraseStudent(id: student.id)
            onChanged()
            dismiss()
        } catch {
            self.error = AppError("Could not erase student.", underlyingError: error)
        }
    }

    private func methodLabel(_ raw: String) -> String? {
        switch raw {
        case "admin_attestation": return "Admin attestation"
        case "parent_in_app":     return "Parent (in-app)"
        default:                  return raw
        }
    }
}

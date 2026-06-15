import SwiftUI

/// Admin queue of pending data-correction requests (PDPA s22). "Apply" writes the
/// requested value onto the student and logs a correction_response disclosure;
/// "Reject" records an optional review note. Reached from StudentManagementView.
struct CorrectionRequestsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var requests: [CorrectionRequest] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var error: AppError?

    @State private var rejectingRequest: CorrectionRequest?
    @State private var rejectNote = ""

    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requests.isEmpty {
                    ContentUnavailableView(
                        "No pending requests",
                        systemImage: "checkmark.seal",
                        description: Text("There are no data-correction requests awaiting review."))
                } else {
                    List {
                        ForEach(requests) { req in
                            Section {
                                LabeledContent("Field", value: req.fieldName)
                                if let cur = req.currentValue {
                                    LabeledContent("Current", value: cur)
                                }
                                LabeledContent("Requested", value: req.requestedValue ?? "—")
                                if let d = req.createdAt {
                                    LabeledContent("Submitted", value: dateFmt.string(from: d))
                                }
                                HStack {
                                    Button {
                                        Task { await apply(req) }
                                    } label: {
                                        Label("Apply", systemImage: "checkmark.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(isWorking)

                                    Spacer()

                                    Button(role: .destructive) {
                                        rejectNote = ""
                                        rejectingRequest = req
                                    } label: {
                                        Label("Reject", systemImage: "xmark.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(isWorking)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Correction Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(isWorking)
                }
            }
            .task { await load() }
            .errorAlert(error: $error)
            .alert("Reject request", isPresented: Binding(
                get: { rejectingRequest != nil },
                set: { if !$0 { rejectingRequest = nil } }
            )) {
                TextField("Reason (optional)", text: $rejectNote)
                Button("Reject", role: .destructive) {
                    if let req = rejectingRequest { Task { await reject(req) } }
                }
                Button("Cancel", role: .cancel) { rejectingRequest = nil }
            } message: {
                Text("Optionally record why this correction was not applied.")
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await AttendanceService.shared.fetchCorrectionRequests(status: .pending)
        } catch {
            self.error = AppError("Could not load correction requests.", underlyingError: error)
        }
    }

    private func apply(_ req: CorrectionRequest) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AttendanceService.shared.applyCorrection(req)
            await load()
        } catch {
            self.error = AppError("Could not apply correction.", underlyingError: error)
        }
    }

    private func reject(_ req: CorrectionRequest) async {
        isWorking = true
        defer { isWorking = false }
        let note = rejectNote.trimmingCharacters(in: .whitespacesAndNewlines)
        rejectingRequest = nil
        do {
            try await AttendanceService.shared.rejectCorrection(id: req.id, note: note.isEmpty ? nil : note)
            await load()
        } catch {
            self.error = AppError("Could not reject correction.", underlyingError: error)
        }
    }
}

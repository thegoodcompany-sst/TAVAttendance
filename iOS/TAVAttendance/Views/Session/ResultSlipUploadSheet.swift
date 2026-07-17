import SwiftUI

struct ResultSlipUploadSheet: View {
    let studentId: UUID
    /// When true, exam name is required and `uploaded_by` is set for parent RLS.
    var requireParentFields: Bool = false
    let onSaved: () async -> Void

    @State private var subject: ResultSlipSubject = .math
    @State private var examName = ""
    @State private var examDate = Date()
    @State private var scoreText = ""
    @State private var maxScoreText = ""
    @State private var isSaving = false
    @State private var saveError: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    private var canSubmit: Bool {
        !isSaving
        && !scoreText.trimmingCharacters(in: .whitespaces).isEmpty
        && !maxScoreText.trimmingCharacters(in: .whitespaces).isEmpty
        && (!requireParentFields || !examName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    Picker("Subject", selection: $subject) {
                        ForEach(ResultSlipSubject.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Exam Details") {
                    TextField(
                        requireParentFields ? "Exam name" : "Exam name (optional)",
                        text: $examName
                    )
                    DatePicker("Date", selection: $examDate, displayedComponents: .date)
                }

                Section {
                    HStack(spacing: 12) {
                        TextField("25", text: $scoreText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text("/")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                        TextField("35", text: $maxScoreText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("Score")
                } footer: {
                    Text("Enter the score as a fraction, e.g. 25 / 35")
                }

                if let err = saveError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Result Slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSubmit)
                    .overlay {
                        if isSaving { ProgressView().scaleEffect(0.8) }
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil

        let trimmedName = examName.trimmingCharacters(in: .whitespacesAndNewlines)
        let score = Double(scoreText.trimmingCharacters(in: .whitespaces))
        let maxScore = Double(maxScoreText.trimmingCharacters(in: .whitespaces))

        if requireParentFields {
            if let failure = ResultSlipInputValidation.validate(
                examName: trimmedName, score: score, maxScore: maxScore
            ) {
                saveError = failure.message
                isSaving = false
                return
            }
            guard let score, let maxScore, let userId = authManager.currentProfile?.id else {
                saveError = String(localized: "Couldn't submit result. Please try again.")
                isSaving = false
                return
            }

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            dateFmt.locale = Locale(identifier: "en_US_POSIX")

            do {
                _ = try await AttendanceService.shared.submitResultSlip(
                    studentId: studentId,
                    examName: trimmedName,
                    examDate: dateFmt.string(from: examDate),
                    subject: subject.rawValue,
                    score: score,
                    maxScore: maxScore,
                    uploadedBy: userId
                )
                await onSaved()
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
            return
        }

        // Staff path: optional fields, no uploaded_by requirement.
        struct SlipMetadataInsert: Encodable {
            let studentId: UUID
            let examName: String?
            let examDate: String?
            let subject: String?
            let score: Double?
            let maxScore: Double?

            enum CodingKeys: String, CodingKey {
                case studentId = "student_id"
                case examName  = "exam_name"
                case examDate  = "exam_date"
                case subject
                case score
                case maxScore  = "max_score"
            }
        }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        let insert = SlipMetadataInsert(
            studentId: studentId,
            examName: trimmedName.isEmpty ? nil : trimmedName,
            examDate: dateFmt.string(from: examDate),
            subject: subject.rawValue,
            score: score,
            maxScore: maxScore
        )

        do {
            let _: ResultSlip = try await SupabaseManager.shared.client
                .from("result_slips")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            await onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }
}

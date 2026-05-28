import SwiftUI

struct ResultSlipUploadSheet: View {
    let studentId: UUID
    let onSaved: () async -> Void

    @State private var subject: ResultSlipSubject = .math
    @State private var examName = ""
    @State private var examDate = Date()
    @State private var scoreText = ""
    @State private var maxScoreText = ""
    @State private var isSaving = false
    @State private var saveError: String?

    @Environment(\.dismiss) private var dismiss

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
                    TextField("Exam name (optional)", text: $examName)
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
                    .disabled(isSaving)
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

        let insert = SlipMetadataInsert(
            studentId: studentId,
            examName: examName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : examName.trimmingCharacters(in: .whitespaces),
            examDate: dateFmt.string(from: examDate),
            subject: subject.rawValue,
            score: Double(scoreText.trimmingCharacters(in: .whitespaces)),
            maxScore: Double(maxScoreText.trimmingCharacters(in: .whitespaces))
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

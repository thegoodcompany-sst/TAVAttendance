import Foundation
import Supabase

extension AttendanceService {
    // MARK: - PDPA: privacy notice (#N1)

    /// Fetches the current Data Protection Notice. Any authenticated user may read it.
    func fetchPrivacyNotice() async throws -> PolicyDocument? {
        let rows: [PolicyDocument] = try await db.from("policy_documents")
            .select()
            .eq("doc_type", value: "data_protection_notice")
            .eq("is_current", value: true)
            .order("published_at", ascending: false)
            .limit(1)
            .execute().value
        return rows.first
    }

    // MARK: - PDPA: consent ledger (#C1/#C2)

    private struct RecordAdminConsentParams: Encodable {
        let studentId: UUID
        let consentType: String
        let status: String
        let sourceNote: String?

        enum CodingKeys: String, CodingKey {
            case studentId   = "p_student_id"
            case consentType = "p_consent_type"
            case status      = "p_status"
            case sourceNote  = "p_source_note"
        }
    }

    /// Appends a consent row through the shaped database RPC. The database
    /// derives the actor, method, current notice version and timestamp.
    func recordConsent(
        studentId: UUID,
        consentType: String = "data_collection",
        status: ConsentStatus = .granted,
        sourceNote: String? = nil
    ) async throws {
        try await db.rpc(
            "record_admin_consent",
            params: RecordAdminConsentParams(
                studentId: studentId,
                consentType: consentType,
                status: status.rawValue,
                sourceNote: sourceNote
            )
        ).execute()
    }

    /// Records bulk consent via the same shaped RPC for each student. Student
    /// creation itself should normally use create_student_with_consent instead.
    func recordConsentBulk(
        studentIds: [UUID],
        consentType: String = "data_collection"
    ) async throws {
        for studentId in studentIds {
            try await recordConsent(
                studentId: studentId,
                consentType: consentType,
                status: .granted,
                sourceNote: "Bulk CSV import attestation"
            )
        }
    }

    /// Returns the latest consent row per (student, type) for one student, from `current_consent`.
    func fetchCurrentConsent(studentId: UUID) async throws -> [ConsentRecord] {
        return try await db.from("current_consent")
            .select()
            .eq("student_id", value: studentId)
            .execute().value
    }

    /// Withdraws consent by appending a `withdrawn` row (append-only ledger).
    func withdrawConsent(studentId: UUID,
                         consentType: String = "data_collection") async throws {
        try await recordConsent(studentId: studentId, consentType: consentType,
                                status: .withdrawn,
                                sourceNote: "Withdrawn by admin")
    }

    // MARK: - PDPA: erase / pseudonymise (#R1/#R2)

    func anonymiseStudent(id: UUID) async throws {
        throw AppError(
            "Pseudonymisation is available only in the secure admin web dashboard."
        )
    }

    func eraseStudent(id: UUID) async throws {
        throw AppError(
            "Erasure is available only in the secure admin web dashboard."
        )
    }

    // MARK: - PDPA: subject-access export (#A2)

    /// Calls the admin-guarded RPC and returns the raw JSON bytes of the personal-data bundle.
    /// The RPC also logs a `data_disclosures` row server-side.
    func exportStudentPersonalData(id: UUID) async throws -> Data {
        // The RPC returns a JSONB value; capture it as raw Data so we can write it to disk verbatim.
        let response = try await db
            .rpc("export_student_personal_data", params: ["p_student_id": id.uuidString])
            .execute()
        return response.data
    }

    // MARK: - PDPA: correction requests (#A1)

    func fetchCorrectionRequests(status: CorrectionStatus = .pending) async throws -> [CorrectionRequest] {
        return try await db.from("correction_requests")
            .select()
            .eq("status", value: status.rawValue)
            .order("created_at", ascending: false)
            .execute().value
    }

    /// The database reviews, applies and logs the correction atomically.
    func applyCorrection(_ request: CorrectionRequest) async throws {
        try await reviewCorrection(id: request.id, decision: .applied, note: nil)
    }

    func rejectCorrection(id: UUID, note: String?) async throws {
        try await reviewCorrection(id: id, decision: .rejected, note: note)
    }

    private func reviewCorrection(
        id: UUID,
        decision: CorrectionStatus,
        note: String?
    ) async throws {
        struct Params: Encodable {
            let requestId: UUID
            let decision: String
            let reviewNote: String?
            enum CodingKeys: String, CodingKey {
                case requestId = "p_request_id"
                case decision = "p_decision"
                case reviewNote = "p_review_note"
            }
        }
        try await db
            .rpc(
                "review_correction_request",
                params: Params(
                    requestId: id,
                    decision: decision.rawValue,
                    reviewNote: note
                )
            )
            .execute()
    }

}

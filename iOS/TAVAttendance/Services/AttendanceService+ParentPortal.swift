import Foundation
import Supabase

extension AttendanceService {
    func fetchParentAttendanceHistory(
        studentId: UUID,
        limit: Int = 100,
        since: Date? = nil
    ) async throws -> [AttendanceHistoryRecord] {
        if DemoMode.isActive { return DemoStore.shared.fetchStudentAttendanceHistory(studentId: studentId, limit: limit, since: since) }
        struct Params: Encodable {
            let studentId: UUID
            let limit: Int
            let since: String?

            enum CodingKeys: String, CodingKey {
                case studentId = "p_student_id"
                case limit = "p_limit"
                case since = "p_since"
            }
        }

        return try await db.rpc(
            "get_parent_attendance_history",
            params: Params(
                studentId: studentId,
                limit: limit,
                since: since.map(Self.ymdFormatter.string(from:))
            )
        ).execute().value
    }

    // MARK: - Result slips (#20 / parent portal Phase 2)

    /// Parent-safe projection installed by migration 038.
    func fetchResultSlips(studentId: UUID) async throws -> [ResultSlip] {
        if DemoMode.isActive { return DemoStore.shared.fetchResultSlips(studentId: studentId) }
        return try await db.rpc(
            "get_parent_result_slips",
            params: ["p_student_id": studentId.uuidString]
        ).execute().value
    }

    /// Staff retain their RLS-scoped base-table view.
    func fetchStaffResultSlips(studentId: UUID) async throws -> [ResultSlip] {
        if DemoMode.isActive { return DemoStore.shared.fetchResultSlips(studentId: studentId) }
        return try await db.from("result_slips")
            .select()
            .eq("student_id", value: studentId)
            .order("uploaded_at", ascending: false)
            .execute().value
    }

    /// Parent-only text result submission; the server derives uploaded_by from auth.uid().
    func submitResultSlip(
        studentId: UUID,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double
    ) async throws -> ResultSlip {
        if DemoMode.isActive { return DemoStore.shared.createResultSlip(studentId: studentId, examName: examName, examDate: examDate, subject: subject, score: score, maxScore: maxScore) }
        struct Params: Encodable {
            let studentId: UUID
            let examName: String
            let examDate: String
            let subject: String
            let score: Double
            let maxScore: Double

            enum CodingKeys: String, CodingKey {
                case studentId = "p_student_id"
                case examName  = "p_exam_name"
                case examDate  = "p_exam_date"
                case subject   = "p_subject"
                case score     = "p_score"
                case maxScore  = "p_max_score"
            }
        }
        let rows: [ResultSlip] = try await db.rpc(
            "submit_parent_result_slip",
            params: Params(
                studentId: studentId,
                examName: examName,
                examDate: examDate,
                subject: subject,
                score: score,
                maxScore: maxScore
            )
        ).execute().value
        guard let result = rows.first else {
            throw AppError("Result submission returned no result.")
        }
        return result
    }

    // MARK: - Parent messages (Phase 2)

    func fetchMessages(studentId: UUID) async throws -> [ParentMessage] {
        if DemoMode.isActive { return DemoStore.shared.fetchMessages(studentId: studentId) }
        return try await db.rpc(
            "get_parent_messages",
            params: ["p_student_id": studentId.uuidString]
        ).execute().value
    }

    func sendParentMessage(
        studentId: UUID,
        subject: String?,
        body: String
    ) async throws -> ParentMessage {
        let nric = try Regex(#"\b[STFGM]\d{7}[A-Z]\b"#).ignoresCase()
        if subject?.contains(nric) == true || body.contains(nric) {
            throw AppError("Messages must not contain an NRIC/FIN.")
        }
        if DemoMode.isActive { return DemoStore.shared.sendMessage(studentId: studentId, subject: subject, body: body) }
        struct Params: Encodable {
            let studentId: UUID
            let subject: String?
            let body: String

            enum CodingKeys: String, CodingKey {
                case studentId = "p_student_id"
                case subject   = "p_subject"
                case body      = "p_body"
            }
        }
        let rows: [ParentMessage] = try await db.rpc(
            "send_parent_message",
            params: Params(
                studentId: studentId,
                subject: subject,
                body: body
            )
        ).execute().value
        guard let message = rows.first else {
            throw AppError("Message submission returned no result.")
        }
        return message
    }

    // MARK: - Parent linking (#13)

    func fetchParents() async throws -> [Profile] {
        if DemoMode.isActive { return DemoStore.shared.fetchParents() }
        return try await db.from("profiles")
            .select()
            .eq("role", value: "parent")
            .order("full_name")
            .execute().value
    }

    func fetchParentLinks(parentId: UUID) async throws -> [UUID] {
        if DemoMode.isActive { return DemoStore.shared.fetchParentLinks(parentId: parentId) }
        struct Link: Codable { let studentId: UUID; enum CodingKeys: String, CodingKey { case studentId = "student_id" } }
        let rows: [Link] = try await db.from("parent_student_links")
            .select("student_id")
            .eq("parent_id", value: parentId)
            .execute().value
        return rows.map(\.studentId)
    }

    func linkParentToStudent(parentId: UUID, studentId: UUID) async throws {
        if DemoMode.isActive { return DemoStore.shared.linkParent(parentId: parentId, studentId: studentId) }
        try await db.rpc("link_parent_student", params: [
            "p_parent": parentId.uuidString,
            "p_student": studentId.uuidString
        ]).execute()
    }

    func unlinkParentFromStudent(parentId: UUID, studentId: UUID) async throws {
        if DemoMode.isActive { return DemoStore.shared.unlinkParent(parentId: parentId, studentId: studentId) }
        try await db.rpc("unlink_parent_student", params: [
            "p_parent": parentId.uuidString,
            "p_student": studentId.uuidString
        ]).execute()
    }

}

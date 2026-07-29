import Foundation
import Supabase

extension AttendanceService {
    // MARK: - Student photos (PROD-04, flag: student_photos)

    /// Uploads a student photo to the `student-photos` bucket and stores its path
    /// on the student row. Returns the storage path.
    func uploadStudentPhoto(studentId: UUID, fileData: Data, fileName: String, mime: String) async throws -> String {
        let maxBytes = 5 * 1024 * 1024
        guard fileData.count <= maxBytes else {
            throw AppError("This photo is too large. Please choose an image under 5 MB.")
        }
        let path = "\(studentId.uuidString.lowercased())/\(UUID().uuidString)-\(fileName)"
        try await db.storage.from("student-photos")
            .upload(path: path, file: fileData, options: .init(contentType: mime, upsert: true))
        try await db.from("students")
            .update(["avatar_url": path])
            .eq("id", value: studentId)
            .execute()
        return path
    }

    /// A short-lived signed URL for a private student photo path.
    func signedStudentPhotoURL(path: String) async throws -> URL {
        try await db.storage.from("student-photos").createSignedURL(path: path, expiresIn: 3600)
    }

    // MARK: - Device tokens (PROD-02, flag: push_notifications)

    /// Registers this device's push token for the signed-in user so the
    /// notify-parent edge function can reach them. Idempotent on the token.
    func registerDeviceToken(_ token: String, platform: String = "ios") async throws {
        struct Params: Encodable {
            let token: String; let platform: String
            enum CodingKeys: String, CodingKey {
                case token = "p_token"; case platform = "p_platform"
            }
        }
        try await db.rpc(
            "register_device_token",
            params: Params(token: token, platform: platform)
        ).execute()
    }

    // MARK: - Export helpers (#7)

    /// Fetches all attendance records for a class within a date range, for export.
    ///
    /// DOC-05: the `session:sessions!inner(...)` modifier is an INNER join — the
    /// `!inner` is required so that records whose session falls outside the date
    /// filter are excluded. Dropping `!inner` would turn this into a LEFT join and
    /// pull in every attendance row regardless of `session.session_date`. See
    /// PostgREST resource embedding docs ("!inner").
    ///
    /// QA-04 / MAINT-06: returns the joined `session_date` so the export uses the
    /// true session date (not `marked_at`, which is wrong for offline-synced rows).
    func fetchAttendanceForExport(classId: UUID, from: Date, to: Date) async throws -> [AttendanceExportRecord] {
        let fmt = Self.ymdFormatter
        return try await db.from("attendance_records")
            .select("student_id, status, marked_at, late_reason, session:sessions!inner(session_date, class_id)")
            .eq("session.class_id", value: classId.uuidString)
            .gte("session.session_date", value: fmt.string(from: from))
            .lte("session.session_date", value: fmt.string(from: to))
            .order("session.session_date", ascending: true)
            .execute().value
    }
}

/// Attendance row joined with its session date, used by the export screen.
/// QA-04: carries the authoritative `session_date` so the CSV/PDF "Date" column
/// is correct even for records that were marked offline and synced on a later day.
struct AttendanceExportRecord: Codable {
    let studentId: UUID
    let status: AttendanceStatus
    let markedAt: Date?
    let lateReason: String?
    let session: SessionDate

    /// The session date is the true class date; `sessionDate` is "yyyy-MM-dd".
    var sessionDate: String { session.sessionDate }

    struct SessionDate: Codable {
        let sessionDate: String
        enum CodingKeys: String, CodingKey { case sessionDate = "session_date" }
    }

    enum CodingKeys: String, CodingKey {
        case studentId  = "student_id"
        case status
        case markedAt   = "marked_at"
        case lateReason = "late_reason"
        case session
    }
}

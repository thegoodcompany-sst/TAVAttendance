import Supabase
import Foundation

// Single service for all Supabase calls. Views never call the client directly.

final class AttendanceService {
    static let shared = AttendanceService()
    private let db = SupabaseManager.shared.client
    private init() {}

    // MARK: - Classes

    func fetchClasses() async throws -> [TAVClass] {
        try await db
            .from("classes")
            .select()
            .eq("is_active", value: true)
            .order("name")
            .execute()
            .value
    }

    // MARK: - Sessions

    func fetchSessions(classId: UUID, limit: Int = 20) async throws -> [TAVSession] {
        try await db
            .from("sessions")
            .select()
            .eq("class_id", value: classId)
            .order("session_date", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Returns today's session for a class, creating it if it doesn't exist yet.
    func getOrCreateTodaySession(classId: UUID) async throws -> TAVSession {
        let today = ISO8601DateFormatter.yyyyMMdd.string(from: Date())

        let existing: [TAVSession] = try await db
            .from("sessions")
            .select()
            .eq("class_id", value: classId)
            .eq("session_date", value: today)
            .execute()
            .value

        if let session = existing.first { return session }

        return try await db
            .from("sessions")
            .insert(["class_id": classId.uuidString, "session_date": today])
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Roster

    /// Returns enrolled students with their current attendance status for a session.
    func fetchRoster(sessionId: UUID) async throws -> [RosterEntry] {
        try await db
            .rpc("get_session_roster", params: ["p_session_id": sessionId.uuidString])
            .execute()
            .value
    }

    // MARK: - Mark Attendance (online)

    func markAttendance(
        sessionId: UUID,
        studentId: UUID,
        status: AttendanceStatus,
        notes: String? = nil
    ) async throws {
        let record = AttendanceInsert(
            sessionId:        sessionId,
            studentId:        studentId,
            status:           status,
            notes:            notes,
            clientMutationId: UUID().uuidString
        )
        try await db
            .from("attendance_records")
            .upsert(record, onConflict: "session_id,student_id")
            .execute()
    }

    // MARK: - Offline Sync

    /// Pushes all unsynced local records to Supabase.
    /// Call when NetworkMonitor.isConnected transitions to true.
    func syncPending() async throws {
        let unsynced = PendingAttendanceStore.shared.pendingUnsynced()
        guard !unsynced.isEmpty else { return }

        let isoFormatter = ISO8601DateFormatter()
        let payload = unsynced.map { r -> [String: String] in
            [
                "session_id":         r.sessionId.uuidString,
                "student_id":         r.studentId.uuidString,
                "status":             r.status.rawValue,
                "notes":              r.notes ?? "",
                "client_mutation_id": r.clientMutationId,
                "marked_at":          isoFormatter.string(from: r.markedAt)
            ]
        }

        let result: [String: Int] = try await db
            .rpc("sync_attendance", params: ["records": payload])
            .execute()
            .value

        let syncedIds = Set(unsynced.map(\.clientMutationId))
        PendingAttendanceStore.shared.markSynced(clientMutationIds: syncedIds)

        print("AttendanceService: synced \(result["synced"] ?? 0), skipped \(result["skipped"] ?? 0)")
    }
}

// MARK: - Date Helpers

private extension ISO8601DateFormatter {
    static let yyyyMMdd: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

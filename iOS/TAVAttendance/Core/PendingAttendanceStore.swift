import Foundation

struct PendingAttendanceRecord: Codable {
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    var notes: String?
    // var (not let): an in-place correction reassigns a fresh clientMutationId and
    // markedAt so an in-flight sync of the old id can't clobber the newer tap.
    var clientMutationId: String
    var markedAt: Date
    var isSynced: Bool
}

final class PendingAttendanceStore: ObservableObject {
    // Singleton: the store is a write-through cache over one shared UserDefaults key,
    // so separate instances would clobber each other. All callers use `.shared`.
    static let shared = PendingAttendanceStore()
    private init() {}

    private let key = "pendingAttendance"

    // In-memory cache — loaded once on first access, then kept in sync via write-through.
    // This avoids re-decoding UserDefaults on every read/write call.
    private var _cache: [PendingAttendanceRecord]?
    private var cache: [PendingAttendanceRecord] {
        get {
            if let c = _cache { return c }
            guard let data = UserDefaults.standard.data(forKey: key),
                  let records = try? JSONDecoder().decode([PendingAttendanceRecord].self, from: data) else {
                _cache = []
                return []
            }
            _cache = records
            return records
        }
        set {
            _cache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    func add(sessionId: UUID, studentId: UUID, status: AttendanceStatus, notes: String?) {
        var records = cache
        if let index = records.firstIndex(where: { $0.sessionId == sessionId && $0.studentId == studentId }) {
            records[index].status = status
            records[index].notes = notes
            // Fresh id + timestamp: this is a NEW mutation. Reusing the old
            // clientMutationId would let an in-flight sync's markSynced() delete this
            // corrected record; a newer markedAt also wins the server's
            // `marked_at <= EXCLUDED.marked_at` conflict guard.
            records[index].clientMutationId = UUID().uuidString
            records[index].markedAt = Date()
        } else {
            let record = PendingAttendanceRecord(
                sessionId: sessionId,
                studentId: studentId,
                status: status,
                notes: notes,
                clientMutationId: UUID().uuidString,
                markedAt: Date(),
                isSynced: false
            )
            records.append(record)
        }
        cache = records
    }

    func allPending() -> [PendingAttendanceRecord] {
        return cache.filter { !$0.isSynced }
    }

    /// Removes successfully-synced records from the store entirely so UserDefaults
    /// does not grow unbounded over time.
    func markSynced(clientMutationIds: Set<String>) {
        cache = cache.filter { !clientMutationIds.contains($0.clientMutationId) }
    }
}

import Foundation

struct PendingAttendanceRecord: Codable {
    let ownerUserId: UUID
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

struct PendingAttendanceEnvelope: Codable {
    let version: Int
    let ownerUserId: UUID
    let records: [PendingAttendanceRecord]
}

enum PendingAttendanceQueueCodec {
    static let version = 2

    static func recordsBelongToOwner(
        _ records: [PendingAttendanceRecord],
        ownerUserId: UUID
    ) -> Bool {
        records.allSatisfy { $0.ownerUserId == ownerUserId }
    }

    static func encode(ownerUserId: UUID, records: [PendingAttendanceRecord]) -> Data? {
        guard recordsBelongToOwner(records, ownerUserId: ownerUserId) else { return nil }
        return try? JSONEncoder().encode(PendingAttendanceEnvelope(
            version: version,
            ownerUserId: ownerUserId,
            records: records
        ))
    }

    /// Returns nil for malformed, legacy-unowned, wrong-owner, or mixed-owner data.
    static func decode(_ data: Data, expectedOwnerUserId: UUID) -> [PendingAttendanceRecord]? {
        guard let envelope = try? JSONDecoder().decode(PendingAttendanceEnvelope.self, from: data),
              envelope.version == version,
              envelope.ownerUserId == expectedOwnerUserId,
              recordsBelongToOwner(envelope.records, ownerUserId: expectedOwnerUserId) else {
            return nil
        }
        return envelope.records
    }
}

@MainActor
final class PendingAttendanceStore: ObservableObject {
    // Singleton: ownership state and the write-through UserDefaults key must move
    // atomically across sign-in/sign-out transitions.
    static let shared = PendingAttendanceStore()
    private init() {}

    private let key = "pendingAttendance"
    private var activeOwnerUserId: UUID?

    /// Activates the authenticated account and purges legacy or foreign queues.
    func activateOwner(_ ownerUserId: UUID) {
        activeOwnerUserId = ownerUserId
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if PendingAttendanceQueueCodec.decode(data, expectedOwnerUserId: ownerUserId) == nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func clear() {
        activeOwnerUserId = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load(ownerUserId: UUID) -> [PendingAttendanceRecord] {
        guard activeOwnerUserId == ownerUserId,
              let data = UserDefaults.standard.data(forKey: key) else { return [] }
        guard let records = PendingAttendanceQueueCodec.decode(
            data,
            expectedOwnerUserId: ownerUserId
        ) else {
            UserDefaults.standard.removeObject(forKey: key)
            return []
        }
        return records
    }

    private func save(ownerUserId: UUID, records: [PendingAttendanceRecord]) -> Bool {
        guard activeOwnerUserId == ownerUserId,
              let data = PendingAttendanceQueueCodec.encode(
                ownerUserId: ownerUserId,
                records: records
              ) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    @discardableResult
    func add(
        ownerUserId: UUID,
        sessionId: UUID,
        studentId: UUID,
        status: AttendanceStatus,
        notes: String?
    ) -> Bool {
        guard activeOwnerUserId == ownerUserId else { return false }
        var records = load(ownerUserId: ownerUserId)
        if let index = records.firstIndex(where: { $0.sessionId == sessionId && $0.studentId == studentId }) {
            records[index].status = status
            records[index].notes = notes
            // Fresh id + timestamp: this is a NEW mutation. Reusing the old
            // clientMutationId would let an in-flight sync's markSynced() delete this
            // corrected record; a newer markedAt also wins the server's
            // `marked_at <= EXCLUDED.marked_at` conflict guard.
            records[index].clientMutationId = UUID().uuidString
            records[index].markedAt = Date()
            records[index].isSynced = false
        } else {
            let record = PendingAttendanceRecord(
                ownerUserId: ownerUserId,
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
        return save(ownerUserId: ownerUserId, records: records)
    }

    func allPending(ownerUserId: UUID) -> [PendingAttendanceRecord] {
        load(ownerUserId: ownerUserId).filter { !$0.isSynced }
    }

    /// Removes successfully-synced records from the store entirely so UserDefaults
    /// does not grow unbounded over time.
    func markSynced(ownerUserId: UUID, clientMutationIds: Set<String>) {
        guard activeOwnerUserId == ownerUserId else { return }
        let remaining = load(ownerUserId: ownerUserId).filter {
            !$0.isSynced && !clientMutationIds.contains($0.clientMutationId)
        }
        _ = save(ownerUserId: ownerUserId, records: remaining)
    }
}

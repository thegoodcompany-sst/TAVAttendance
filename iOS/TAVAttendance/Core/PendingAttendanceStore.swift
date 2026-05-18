import Foundation

// Persists unsynced attendance records to UserDefaults.
// Swapped for CoreData if the queue grows large.

final class PendingAttendanceStore {
    static let shared = PendingAttendanceStore()

    private let key = "tava.pending_attendance"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Read / Write

    func load() -> [PendingAttendanceRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? decoder.decode([PendingAttendanceRecord].self, from: data)
        else { return [] }
        return records
    }

    private func save(_ records: [PendingAttendanceRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Queue / Update

    func upsert(sessionId: UUID, studentId: UUID, status: AttendanceStatus, notes: String? = nil) {
        var records = load()
        if let idx = records.firstIndex(where: {
            $0.sessionId == sessionId && $0.studentId == studentId
        }) {
            records[idx].status   = status
            records[idx].notes    = notes
            records[idx].isSynced = false
        } else {
            records.append(PendingAttendanceRecord(
                sessionId:        sessionId,
                studentId:        studentId,
                status:           status,
                notes:            notes,
                clientMutationId: UUID().uuidString,
                markedAt:         Date(),
                isSynced:         false
            ))
        }
        save(records)
    }

    func markSynced(clientMutationIds: Set<String>) {
        var records = load()
        for i in records.indices where clientMutationIds.contains(records[i].clientMutationId) {
            records[i].isSynced = true
        }
        save(records)
    }

    func pendingUnsynced() -> [PendingAttendanceRecord] {
        load().filter { !$0.isSynced }
    }
}

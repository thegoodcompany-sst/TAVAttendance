import Foundation

struct PendingAttendanceRecord: Codable {
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus
    var notes: String?
    let clientMutationId: String
    let markedAt: Date
    var isSynced: Bool
}

final class PendingAttendanceStore: ObservableObject {
    private let key = "pendingAttendance"

    private func load() -> [PendingAttendanceRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([PendingAttendanceRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func save(_ records: [PendingAttendanceRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(sessionId: UUID, studentId: UUID, status: AttendanceStatus, notes: String?) {
        var records = load()
        if let index = records.firstIndex(where: { $0.sessionId == sessionId && $0.studentId == studentId }) {
            records[index].status = status
            records[index].notes = notes
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
        save(records)
    }

    func allPending() -> [PendingAttendanceRecord] {
        return load().filter { !$0.isSynced }
    }

    func markSynced(clientMutationIds: Set<String>) {
        var records = load()
        for index in records.indices {
            if clientMutationIds.contains(records[index].clientMutationId) {
                records[index].isSynced = true
            }
        }
        save(records)
    }
}

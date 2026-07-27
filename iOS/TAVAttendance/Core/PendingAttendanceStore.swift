import Foundation
import CryptoKit
import Security

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

enum PendingAttendanceQueueCipher {
    private static let version: UInt8 = 1
    private static let authenticatedContext = Data("pendingAttendance".utf8)

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: authenticatedContext
        )
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return Data([version]) + combined
    }

    static func open(_ payload: Data, using key: SymmetricKey) throws -> Data {
        guard payload.first == version else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let box = try AES.GCM.SealedBox(combined: payload.dropFirst())
        return try AES.GCM.open(
            box,
            using: key,
            authenticating: authenticatedContext
        )
    }
}

private enum PendingAttendanceQueueKeychain {
    private static let service = "com.tava.TAVAttendance.pending-attendance"
    private static let account = "aes-gcm-v1"
    private static let keyBytes = 32

    static func loadOrCreate() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == keyBytes {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { return nil }

        var bytes = Data(count: keyBytes)
        let randomStatus = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, keyBytes, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { return nil }

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            // Another process may have won the create race.
            return loadExisting()
        }
        return SymmetricKey(data: bytes)
    }

    private static func loadExisting() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == keyBytes else { return nil }
        return SymmetricKey(data: data)
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
        if decryptAndDecode(data, ownerUserId: ownerUserId) != nil { return }

        // One-time migration from the former plaintext JSON value. Only replace
        // it after the encrypted write can be read back successfully.
        if let legacy = PendingAttendanceQueueCodec.decode(data, expectedOwnerUserId: ownerUserId),
           save(ownerUserId: ownerUserId, records: legacy) {
            return
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    func clear() {
        activeOwnerUserId = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load(ownerUserId: UUID) -> [PendingAttendanceRecord] {
        guard activeOwnerUserId == ownerUserId,
              let data = UserDefaults.standard.data(forKey: key) else { return [] }
        guard let records = decryptAndDecode(data, ownerUserId: ownerUserId) else {
            UserDefaults.standard.removeObject(forKey: key)
            return []
        }
        return records
    }

    private func decryptAndDecode(
        _ encrypted: Data,
        ownerUserId: UUID
    ) -> [PendingAttendanceRecord]? {
        guard let key = PendingAttendanceQueueKeychain.loadOrCreate(),
              let plaintext = try? PendingAttendanceQueueCipher.open(encrypted, using: key) else {
            return nil
        }
        return PendingAttendanceQueueCodec.decode(
            plaintext,
            expectedOwnerUserId: ownerUserId
        )
    }

    private func save(ownerUserId: UUID, records: [PendingAttendanceRecord]) -> Bool {
        guard activeOwnerUserId == ownerUserId,
              let plaintext = PendingAttendanceQueueCodec.encode(
                ownerUserId: ownerUserId,
                records: records
              ),
              let encryptionKey = PendingAttendanceQueueKeychain.loadOrCreate(),
              let encrypted = try? PendingAttendanceQueueCipher.seal(
                plaintext,
                using: encryptionKey
              ),
              decryptAndDecode(encrypted, ownerUserId: ownerUserId) != nil else {
            return false
        }
        UserDefaults.standard.set(encrypted, forKey: key)
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

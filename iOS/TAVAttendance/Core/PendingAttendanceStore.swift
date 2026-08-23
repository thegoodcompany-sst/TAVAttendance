import Foundation
import CryptoKit
import Security

struct PendingAttendanceRecord: Codable {
    let ownerUserId: UUID
    let sessionId: UUID
    let studentId: UUID
    var status: AttendanceStatus?
    var notes: String?
    var absenceInformed: Bool?
    // var (not let): an in-place correction reassigns a fresh clientMutationId and
    // markedAt so an in-flight sync of the old id can't clobber the newer tap.
    var clientMutationId: String
    var markedAt: Date
    var isSynced: Bool
    /// Last **server** `marked_at` the roster showed when this row was first
    /// queued. Nil means the client observed no attendance row. Never the
    /// device queue timestamp (`markedAt` above).
    var observedMarkedAt: Date?
    /// False for migrated v3 envelopes that omitted the observation. New
    /// queue writes always observe the roster and set this true.
    var didObserveRow: Bool

    enum CodingKeys: String, CodingKey {
        case ownerUserId, sessionId, studentId, status, notes
        case absenceInformed, clientMutationId, markedAt, isSynced
        case observedMarkedAt = "observed_marked_at"
        case didObserveRow
    }

    init(
        ownerUserId: UUID,
        sessionId: UUID,
        studentId: UUID,
        status: AttendanceStatus?,
        notes: String?,
        absenceInformed: Bool?,
        clientMutationId: String,
        markedAt: Date,
        isSynced: Bool,
        observedMarkedAt: Date? = nil,
        didObserveRow: Bool = false
    ) {
        self.ownerUserId = ownerUserId
        self.sessionId = sessionId
        self.studentId = studentId
        self.status = status
        self.notes = notes
        self.absenceInformed = absenceInformed
        self.clientMutationId = clientMutationId
        self.markedAt = markedAt
        self.isSynced = isSynced
        self.observedMarkedAt = observedMarkedAt
        self.didObserveRow = didObserveRow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownerUserId = try container.decode(UUID.self, forKey: .ownerUserId)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        studentId = try container.decode(UUID.self, forKey: .studentId)
        status = try container.decodeIfPresent(AttendanceStatus.self, forKey: .status)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        absenceInformed = try container.decodeIfPresent(Bool.self, forKey: .absenceInformed)
        clientMutationId = try container.decode(String.self, forKey: .clientMutationId)
        markedAt = try container.decode(Date.self, forKey: .markedAt)
        isSynced = try container.decode(Bool.self, forKey: .isSynced)
        observedMarkedAt = try container.decodeIfPresent(Date.self, forKey: .observedMarkedAt)
        if let flag = try container.decodeIfPresent(Bool.self, forKey: .didObserveRow) {
            didObserveRow = flag
        } else {
            // v3 envelopes omit the key. Presence of observed_marked_at
            // (including JSON null) means this client observed the roster.
            didObserveRow = container.contains(.observedMarkedAt)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownerUserId, forKey: .ownerUserId)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(studentId, forKey: .studentId)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(absenceInformed, forKey: .absenceInformed)
        try container.encode(clientMutationId, forKey: .clientMutationId)
        try container.encode(markedAt, forKey: .markedAt)
        try container.encode(isSynced, forKey: .isSynced)
        try container.encode(didObserveRow, forKey: .didObserveRow)
        if didObserveRow {
            if let observedMarkedAt {
                try container.encode(observedMarkedAt, forKey: .observedMarkedAt)
            } else {
                try container.encodeNil(forKey: .observedMarkedAt)
            }
        }
    }

    /// Rotates mutation identity for a new local correction. The original
    /// observed server `marked_at` snapshot is preserved for CAS.
    mutating func applyCorrection(
        status: AttendanceStatus?,
        notes: String?,
        absenceInformed: Bool?,
        markedAt: Date = Date(),
        clientMutationId: String = UUID().uuidString
    ) {
        self.status = status
        self.notes = notes
        self.absenceInformed = absenceInformed
        self.clientMutationId = clientMutationId
        self.markedAt = markedAt
        self.isSynced = false
    }
}

struct PendingAttendanceEnvelope: Codable {
    let version: Int
    let ownerUserId: UUID
    let records: [PendingAttendanceRecord]
}

private struct LegacyPendingAttendanceRecord: Codable {
    let ownerUserId: UUID
    let sessionId: UUID
    let studentId: UUID
    let status: String
    let notes: String?
    let clientMutationId: String
    let markedAt: Date
    let isSynced: Bool
}

private struct LegacyPendingAttendanceEnvelope: Codable {
    let version: Int
    let ownerUserId: UUID
    let records: [LegacyPendingAttendanceRecord]
}

enum PendingAttendanceQueueCodec {
    static let version = 4
    /// v3 envelopes lack `observed_marked_at`; decode them as unknown observation.
    private static let previousVersion = 3

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
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(PendingAttendanceEnvelope.self, from: data),
           (envelope.version == version || envelope.version == previousVersion),
           envelope.ownerUserId == expectedOwnerUserId,
           recordsBelongToOwner(envelope.records, ownerUserId: expectedOwnerUserId) {
            return envelope.records
        }
        guard let envelope = try? decoder.decode(LegacyPendingAttendanceEnvelope.self, from: data),
              envelope.version == 2,
              envelope.ownerUserId == expectedOwnerUserId else { return nil }
        let records = envelope.records.map {
            PendingAttendanceRecord(
                ownerUserId: $0.ownerUserId,
                sessionId: $0.sessionId,
                studentId: $0.studentId,
                status: AttendanceStatus(rawValue: $0.status),
                notes: $0.notes,
                absenceInformed: nil,
                clientMutationId: $0.clientMutationId,
                markedAt: $0.markedAt,
                isSynced: $0.isSynced,
                observedMarkedAt: nil,
                didObserveRow: false
            )
        }
        return recordsBelongToOwner(records, ownerUserId: expectedOwnerUserId) ? records : nil
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
        if let records = decryptAndDecode(data, ownerUserId: ownerUserId) {
            _ = save(ownerUserId: ownerUserId, records: records)
            return
        }

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
        status: AttendanceStatus?,
        notes: String?,
        absenceInformed: Bool? = nil,
        observedMarkedAt: Date?
    ) -> Bool {
        guard activeOwnerUserId == ownerUserId else { return false }
        var records = load(ownerUserId: ownerUserId)
        if let index = records.firstIndex(where: { $0.sessionId == sessionId && $0.studentId == studentId }) {
            // Keep the original observed server snapshot from first queue; do
            // not replace it with this tap's local optimistic time.
            records[index].applyCorrection(
                status: status,
                notes: notes,
                absenceInformed: absenceInformed
            )
        } else {
            let record = PendingAttendanceRecord(
                ownerUserId: ownerUserId,
                sessionId: sessionId,
                studentId: studentId,
                status: status,
                notes: notes,
                absenceInformed: absenceInformed,
                clientMutationId: UUID().uuidString,
                markedAt: Date(),
                isSynced: false,
                observedMarkedAt: observedMarkedAt,
                didObserveRow: true
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

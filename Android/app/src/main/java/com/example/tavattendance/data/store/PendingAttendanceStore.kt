package com.example.tavattendance.data.store

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.example.tavattendance.data.models.AttendanceStatus
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val PENDING_QUEUE_VERSION = 3
private const val ANDROID_KEYSTORE = "AndroidKeyStore"
private const val PENDING_QUEUE_KEY_ALIAS = "tava.pending.attendance.aes.v1"
private const val ENCRYPTED_PREFIX = "enc-v1:"
private const val GCM_IV_BYTES = 12
private const val GCM_TAG_BITS = 128
private val PENDING_QUEUE_AAD = "pending_attendance.records".toByteArray(Charsets.UTF_8)
private val pendingQueueJson = Json { ignoreUnknownKeys = true }

@Serializable
data class PendingAttendanceRecord(
    val ownerUserId: String,
    val sessionId: String,
    val studentId: String,
    var status: AttendanceStatus?,
    var notes: String? = null,
    // Optional companion for absent; null-safe so codec version stays at 3.
    var absenceInformed: Boolean? = null,
    val clientMutationId: String,
    val markedAt: String,
    var isSynced: Boolean = false
)

@Serializable
internal data class PendingAttendanceEnvelope(
    val version: Int,
    val ownerUserId: String,
    val records: List<PendingAttendanceRecord>
)

@Serializable
private data class LegacyPendingAttendanceRecord(
    val ownerUserId: String,
    val sessionId: String,
    val studentId: String,
    val status: String,
    val notes: String? = null,
    val clientMutationId: String,
    val markedAt: String,
    val isSynced: Boolean = false,
)

@Serializable
private data class LegacyPendingAttendanceEnvelope(
    val version: Int,
    val ownerUserId: String,
    val records: List<LegacyPendingAttendanceRecord>,
)

private fun canonicalOwnerUserId(ownerUserId: String): String? =
    runCatching { UUID.fromString(ownerUserId).toString() }.getOrNull()

internal fun pendingRecordsBelongToOwner(
    records: List<PendingAttendanceRecord>,
    ownerUserId: String
): Boolean {
    val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return false
    return records.all { canonicalOwnerUserId(it.ownerUserId) == canonicalOwner }
}

private fun PendingAttendanceEnvelope.belongsTo(ownerUserId: String): Boolean {
    val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return false
    return version == PENDING_QUEUE_VERSION &&
        canonicalOwnerUserId(this.ownerUserId) == canonicalOwner &&
        pendingRecordsBelongToOwner(records, canonicalOwner)
}

internal fun encodePendingQueue(
    ownerUserId: String,
    records: List<PendingAttendanceRecord>
): String? {
    val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return null
    if (!pendingRecordsBelongToOwner(records, canonicalOwner)) return null
    return pendingQueueJson.encodeToString(
        PendingAttendanceEnvelope(PENDING_QUEUE_VERSION, canonicalOwner, records)
    )
}

/** Returns null for malformed, legacy-unowned, wrong-owner, or mixed-owner data. */
internal fun decodePendingQueue(raw: String, expectedOwnerUserId: String): List<PendingAttendanceRecord>? {
    val envelope = runCatching {
        pendingQueueJson.decodeFromString<PendingAttendanceEnvelope>(raw)
    }.getOrNull()
    if (envelope?.version == PENDING_QUEUE_VERSION) {
        return envelope.records.takeIf { envelope.belongsTo(expectedOwnerUserId) }
    }

    val legacy = runCatching {
        pendingQueueJson.decodeFromString<LegacyPendingAttendanceEnvelope>(raw)
    }.getOrNull() ?: return null
    val canonicalOwner = canonicalOwnerUserId(expectedOwnerUserId) ?: return null
    if (legacy.version != 2 || canonicalOwnerUserId(legacy.ownerUserId) != canonicalOwner) return null
    return legacy.records.map { record ->
        PendingAttendanceRecord(
            ownerUserId = record.ownerUserId,
            sessionId = record.sessionId,
            studentId = record.studentId,
            status = AttendanceStatus.entries.firstOrNull { it.name == record.status },
            notes = record.notes,
            clientMutationId = record.clientMutationId,
            markedAt = record.markedAt,
            isSynced = record.isSynced,
        )
    }.takeIf { pendingRecordsBelongToOwner(it, canonicalOwner) }
}

internal object PendingQueueCipher {
    fun seal(plaintext: String, key: SecretKey): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, SecureRandom())
        cipher.updateAAD(PENDING_QUEUE_AAD)
        check(cipher.iv.size == GCM_IV_BYTES) { "Unexpected AES-GCM nonce size" }
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return ENCRYPTED_PREFIX + Base64.getEncoder().encodeToString(cipher.iv + ciphertext)
    }

    fun open(payload: String, key: SecretKey): String {
        require(payload.startsWith(ENCRYPTED_PREFIX)) { "Unknown queue encryption version" }
        val combined = Base64.getDecoder().decode(payload.removePrefix(ENCRYPTED_PREFIX))
        require(combined.size >= GCM_IV_BYTES + GCM_TAG_BITS / 8) {
            "Encrypted queue is truncated"
        }
        val iv = combined.copyOfRange(0, GCM_IV_BYTES)
        val ciphertext = combined.copyOfRange(GCM_IV_BYTES, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(PENDING_QUEUE_AAD)
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }
}

class PendingAttendanceStore(context: Context) {
    private val prefs = context.getSharedPreferences("pending_attendance", Context.MODE_PRIVATE)
    private val key = "records"

    companion object {
        private val queueLock = Any()

        @Volatile
        private var activeOwnerUserId: String? = null
    }

    /** Activates the authenticated account and purges legacy or foreign queues. */
    fun activateOwner(ownerUserId: String): Boolean {
        val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: run {
            clear()
            return false
        }
        synchronized(queueLock) {
            activeOwnerUserId = canonicalOwner
            val raw = prefs.getString(key, null) ?: return true
            decryptAndDecode(raw, canonicalOwner)?.let { records ->
                saveLocked(canonicalOwner, records)
                return true
            }

            // One-time migration from the former plaintext JSON preference.
            // saveLocked verifies the encrypted value before it replaces it.
            val legacy = decodePendingQueue(raw, canonicalOwner)
            if (legacy != null && saveLocked(canonicalOwner, legacy)) {
                return true
            }
            prefs.edit().remove(key).commit()
            return true
        }
    }

    fun clear() {
        synchronized(queueLock) {
            activeOwnerUserId = null
            // commit() makes sign-out/account transitions an immediate security boundary.
            prefs.edit().remove(key).commit()
        }
    }

    private fun loadLocked(ownerUserId: String): List<PendingAttendanceRecord> {
        val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return emptyList()
        if (activeOwnerUserId != canonicalOwner) return emptyList()
        val raw = prefs.getString(key, null) ?: return emptyList()
        val records = decryptAndDecode(raw, canonicalOwner)
        if (records == null) {
            // Active-account reads fail closed on legacy, corrupt, or mixed-owner data.
            prefs.edit().remove(key).commit()
            return emptyList()
        }
        return records
    }

    private fun saveLocked(ownerUserId: String, records: List<PendingAttendanceRecord>): Boolean {
        val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return false
        if (activeOwnerUserId != canonicalOwner) return false
        val encoded = encodePendingQueue(canonicalOwner, records) ?: return false
        val encrypted = runCatching {
            PendingQueueCipher.seal(encoded, getOrCreateKey())
        }.getOrNull() ?: return false
        if (decryptAndDecode(encrypted, canonicalOwner) == null) return false
        return prefs.edit().putString(key, encrypted).commit()
    }

    private fun decryptAndDecode(
        encrypted: String,
        ownerUserId: String
    ): List<PendingAttendanceRecord>? = runCatching {
        decodePendingQueue(
            PendingQueueCipher.open(encrypted, getOrCreateKey()),
            ownerUserId
        )
    }.getOrNull()

    private fun getOrCreateKey(): SecretKey = synchronized(queueLock) {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(PENDING_QUEUE_KEY_ALIAS, null) as? SecretKey) ?: KeyGenerator
            .getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                        PENDING_QUEUE_KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .setRandomizedEncryptionRequired(true)
                        .build()
                )
            }
            .generateKey()
    }

    fun add(
        ownerUserId: String,
        sessionId: String,
        studentId: String,
        status: AttendanceStatus?,
        notes: String?,
        absenceInformed: Boolean? = null
    ): Boolean = synchronized(queueLock) {
        val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return@synchronized false
        if (activeOwnerUserId != canonicalOwner) return@synchronized false
        val records = loadLocked(canonicalOwner).toMutableList()
        val idx = records.indexOfFirst { it.sessionId == sessionId && it.studentId == studentId }
        if (idx >= 0) {
            // A correction after a prior sync must get a fresh markedAt/clientMutationId and
            // be un-synced, otherwise it silently never uploads (stale isSynced=true) or loses
            // the server's conflict race.
            records[idx] = records[idx].copy(
                status = status,
                notes = notes,
                absenceInformed = absenceInformed,
                markedAt = java.time.Instant.now().toString(),
                clientMutationId = UUID.randomUUID().toString(),
                isSynced = false
            )
        } else {
            records.add(
                PendingAttendanceRecord(
                    ownerUserId = canonicalOwner,
                    sessionId = sessionId,
                    studentId = studentId,
                    status = status,
                    notes = notes,
                    absenceInformed = absenceInformed,
                    clientMutationId = UUID.randomUUID().toString(),
                    markedAt = java.time.Instant.now().toString(),
                    isSynced = false
                )
            )
        }
        saveLocked(canonicalOwner, records)
    }

    fun allPending(ownerUserId: String): List<PendingAttendanceRecord> = synchronized(queueLock) {
        loadLocked(ownerUserId).filter { !it.isSynced }
    }

    fun markSynced(ownerUserId: String, clientMutationIds: Set<String>): Boolean =
        synchronized(queueLock) {
            val canonicalOwner = canonicalOwnerUserId(ownerUserId) ?: return@synchronized false
            if (activeOwnerUserId != canonicalOwner) return@synchronized false
            saveLocked(canonicalOwner, recordsAfterSync(loadLocked(canonicalOwner), clientMutationIds))
        }
}

/** Synced attendance contains student identifiers and has no offline purpose.
 * Remove it immediately, including legacy rows previously retained as synced. */
internal fun recordsAfterSync(
    records: List<PendingAttendanceRecord>,
    clientMutationIds: Set<String>
): List<PendingAttendanceRecord> = records.filterNot {
    it.isSynced || it.clientMutationId in clientMutationIds
}

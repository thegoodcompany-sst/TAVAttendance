package com.example.tavattendance.data.store

import android.content.Context
import com.example.tavattendance.data.models.AttendanceStatus
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

private const val PENDING_QUEUE_VERSION = 2
private val pendingQueueJson = Json { ignoreUnknownKeys = true }

@Serializable
data class PendingAttendanceRecord(
    val ownerUserId: String,
    val sessionId: String,
    val studentId: String,
    var status: AttendanceStatus,
    var notes: String? = null,
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
    }.getOrNull() ?: return null
    return envelope.records.takeIf { envelope.belongsTo(expectedOwnerUserId) }
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
            if (decodePendingQueue(raw, canonicalOwner) == null) {
                prefs.edit().remove(key).commit()
            }
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
        val records = decodePendingQueue(raw, canonicalOwner)
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
        return prefs.edit().putString(key, encoded).commit()
    }

    fun add(
        ownerUserId: String,
        sessionId: String,
        studentId: String,
        status: AttendanceStatus,
        notes: String?
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

package com.example.tavattendance.data.store

import android.content.Context
import com.example.tavattendance.data.models.AttendanceStatus
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class PendingAttendanceRecord(
    val sessionId: String,
    val studentId: String,
    var status: AttendanceStatus,
    var notes: String? = null,
    val clientMutationId: String,
    val markedAt: String,
    var isSynced: Boolean = false
)

class PendingAttendanceStore(context: Context) {
    private val prefs = context.getSharedPreferences("pending_attendance", Context.MODE_PRIVATE)
    private val key = "records"
    private val json = Json { ignoreUnknownKeys = true }

    private fun load(): List<PendingAttendanceRecord> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<PendingAttendanceRecord>>(raw) }.getOrDefault(emptyList())
    }

    private fun save(records: List<PendingAttendanceRecord>) {
        prefs.edit().putString(key, json.encodeToString(records)).apply()
    }

    fun add(sessionId: String, studentId: String, status: AttendanceStatus, notes: String?) {
        val records = load().toMutableList()
        val idx = records.indexOfFirst { it.sessionId == sessionId && it.studentId == studentId }
        if (idx >= 0) {
            // A correction after a prior sync must get a fresh markedAt/clientMutationId and
            // be un-synced, otherwise it silently never uploads (stale isSynced=true) or loses
            // the server's `marked_at <= EXCLUDED.marked_at` ON CONFLICT race.
            records[idx] = records[idx].copy(
                status = status,
                notes = notes,
                markedAt = java.time.Instant.now().toString(),
                clientMutationId = java.util.UUID.randomUUID().toString(),
                isSynced = false
            )
        } else {
            records.add(
                PendingAttendanceRecord(
                    sessionId = sessionId,
                    studentId = studentId,
                    status = status,
                    notes = notes,
                    clientMutationId = java.util.UUID.randomUUID().toString(),
                    markedAt = java.time.Instant.now().toString(),
                    isSynced = false
                )
            )
        }
        save(records)
    }

    fun allPending(): List<PendingAttendanceRecord> = load().filter { !it.isSynced }

    fun markSynced(clientMutationIds: Set<String>) {
        val records = load().map { r ->
            if (r.clientMutationId in clientMutationIds) r.copy(isSynced = true) else r
        }
        save(records)
    }
}

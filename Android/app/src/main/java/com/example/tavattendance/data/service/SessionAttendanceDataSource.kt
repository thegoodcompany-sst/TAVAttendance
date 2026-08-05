package com.example.tavattendance.data.service

import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.*
import com.example.tavattendance.data.store.PendingAttendanceRecord
import com.example.tavattendance.data.store.pendingRecordsBelongToOwner
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.*
import kotlin.time.Duration.Companion.seconds

internal object SessionAttendanceDataSource {
    private val db get() = SupabaseClient.client

    suspend fun fetchSessions(classId: String): List<Session> =
        db.from("sessions").select {
            filter { eq("class_id", classId) }
            order("session_date", Order.DESCENDING)
        }.decodeList<Session>()

    suspend fun getOrCreateTodaySession(classId: String): Session =
        db.postgrest.rpc("get_or_create_today_session", buildJsonObject {
            put("p_class_id", classId)
        }).decodeSingle<Session>()

    suspend fun fetchClass(id: String): TAVClass? =
        ClassStudentDataSource.fetchMyClasses().firstOrNull { it.id == id }

    suspend fun startSession(id: String) {
        db.postgrest.rpc("set_session_lifecycle", buildJsonObject {
            put("p_session_id", id)
            put("p_action", "start")
        })
    }

    suspend fun endSession(id: String) {
        db.postgrest.rpc("set_session_lifecycle", buildJsonObject {
            put("p_session_id", id)
            put("p_action", "end")
        })
    }

    suspend fun createRetrospectiveSession(
        classId: String,
        sessionDate: String,
        topic: String?,
        notes: String?,
        subTutorId: String?
    ): Session = db.postgrest.rpc("create_retrospective_session", buildJsonObject {
        put("class_id", classId)
        put("session_date", sessionDate)
        put("topic", topic?.let(::JsonPrimitive) ?: JsonNull)
        put("notes", notes?.let(::JsonPrimitive) ?: JsonNull)
        put("sub_tutor_id", subTutorId?.let(::JsonPrimitive) ?: JsonNull)
    }).decodeSingle<Session>()

    suspend fun updateRetrospectiveSession(
        sessionId: String,
        topic: String?,
        notes: String?,
        subTutorId: String?
    ): Session = db.postgrest.rpc("update_retrospective_session", buildJsonObject {
        put("session_id", sessionId)
        put("topic", topic?.let(::JsonPrimitive) ?: JsonNull)
        put("notes", notes?.let(::JsonPrimitive) ?: JsonNull)
        put("sub_tutor_id", subTutorId?.let(::JsonPrimitive) ?: JsonNull)
    }).decodeSingle<Session>()

    suspend fun fetchSessionNotes(id: String): String? =
        db.from("sessions").select {
            filter { eq("id", id) }
        }.decodeList<Session>().firstOrNull()?.notes

    suspend fun fetchSession(id: String): Session? =
        db.from("sessions").select {
            filter { eq("id", id) }
        }.decodeList<Session>().firstOrNull()

    /** Saves the tutor's free-text note on a session (flag `session_notes`). Empty note → SQL NULL. */
    suspend fun updateSessionNotes(id: String, notes: String?) {
        db.postgrest.rpc("update_session_note", buildJsonObject {
            put("p_session_id", id)
            put("p_notes", notes?.let(::JsonPrimitive) ?: JsonNull)
        })
    }

    suspend fun fetchRoster(sessionId: String): List<RosterEntry> =
        db.postgrest.rpc("get_session_roster", buildJsonObject { put("p_session_id", sessionId) })
            .decodeList<RosterEntry>()

    suspend fun fetchRetrospectiveRoster(sessionId: String): List<RosterEntry> =
        db.postgrest.rpc(
            "get_retrospective_session_roster",
            buildJsonObject { put("session_id", sessionId) }
        ).decodeList<RosterEntry>()

    suspend fun markRetrospectiveAttendance(
        sessionId: String,
        studentId: String,
        status: AttendanceStatus?
    ) {
        db.postgrest.rpc("mark_retrospective_attendance", buildJsonObject {
            put("session_id", sessionId)
            put("student_id", studentId)
            put("status", status?.name?.let(::JsonPrimitive) ?: JsonNull)
        })
    }

    suspend fun clearAttendance(sessionId: String, studentId: String) {
        db.postgrest.rpc("clear_attendance", buildJsonObject {
            put("p_session_id", sessionId)
            put("p_student_id", studentId)
            put("p_client_mutation_id", UUID.randomUUID().toString())
        })
    }

    suspend fun markAttendance(
        sessionId: String, studentId: String, status: AttendanceStatus, notes: String? = null
    ) {
        val record = AttendanceInsert(
            sessionId = sessionId,
            studentId = studentId,
            status = status,
            notes = notes,
            clientMutationId = UUID.randomUUID().toString()
        )
        db.from("attendance_records").upsert(record) { onConflict = "session_id,student_id" }
    }
    suspend fun fetchStudentAttendanceHistory(
        studentId: String,
        limit: Int = 100,
        since: String? = null
    ): List<AttendanceHistoryRecord> =
        db.from("attendance_records")
            // QA-05: filter the window by session_date (the real class date), not
            // marked_at; `!inner` makes the embedded filter apply to the top-level rows.
            .select(Columns.raw(StudentAttendanceHistoryQuery.SELECT)) {
                filter {
                    eq("student_id", studentId)
                    // Study Space attendance is internal-only — never show it in student history.
                    eq(
                        StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_COLUMN,
                        StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_VALUE
                    )
                    if (since != null) gte("session.session_date", since)
                }
                order("marked_at", Order.DESCENDING)
                limit(limit.toLong())
            }.decodeList<AttendanceHistoryRecord>()

    @Serializable
    private data class SyncRecord(
        @SerialName("session_id") val sessionId: String,
        @SerialName("student_id") val studentId: String,
        val status: String?,
        val notes: String,
        @SerialName("client_mutation_id") val clientMutationId: String,
        @SerialName("marked_at") val markedAt: String
    )

    @Serializable
    private data class SyncParams(val records: List<SyncRecord>)

    /** synced, skipped (newer server record won), blocked_ended_session (session already ended — migration 016). */
    // Result type exposed via AttendanceService.SyncResult

    suspend fun syncPending(records: List<PendingAttendanceRecord>): Triple<Int, Int, Int> {
        val currentUserId = db.auth.currentUserOrNull()?.id
            ?: throw SecurityException("Cannot sync attendance without an authenticated user")
        if (!pendingRecordsBelongToOwner(records, currentUserId)) {
            throw SecurityException("Pending attendance belongs to a different account")
        }
        val payload = records.map { r ->
            SyncRecord(
                sessionId = r.sessionId,
                studentId = r.studentId,
                status = r.status?.name,
                notes = r.notes ?: "",
                clientMutationId = r.clientMutationId,
                markedAt = r.markedAt
            )
        }
        val paramsJson = Json.encodeToJsonElement(SyncParams(payload)).jsonObject
        val result = db.postgrest.rpc("sync_attendance", paramsJson).decodeAs<Map<String, Int>>()
        return Triple(
            result["synced"] ?: 0,
            result["skipped"] ?: 0,
            result["blocked_ended_session"] ?: 0,
        )
    }
}

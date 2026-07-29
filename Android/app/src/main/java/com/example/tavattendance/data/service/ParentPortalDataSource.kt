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

internal object ParentPortalDataSource {
    private val db get() = SupabaseClient.client

    suspend fun fetchParentAttendanceHistory(
        studentId: String,
        limit: Int = 100,
        since: String? = null
    ): List<AttendanceHistoryRecord> =
        db.postgrest.rpc("get_parent_attendance_history", buildJsonObject {
            put("p_student_id", studentId)
            put("p_limit", limit)
            since?.let { put("p_since", it) }
        }).decodeList()
    // ---- Result slips + parent messages (Phase 2 parent portal) ----

    /** Parent-safe projection (migration 038). */
    suspend fun fetchResultSlips(studentId: String): List<ResultSlip> =
        db.postgrest.rpc("get_parent_result_slips", buildJsonObject {
            put("p_student_id", studentId)
        }).decodeList()

    /** Staff retain their RLS-scoped base-table view. */
    suspend fun fetchStaffResultSlips(studentId: String): List<ResultSlip> =
        db.from("result_slips").select {
            filter { eq("student_id", studentId) }
            order("uploaded_at", Order.DESCENDING)
        }.decodeList()

    /** Parent-only text result submission; the server derives uploaded_by from auth.uid(). */
    suspend fun submitResultSlip(
        studentId: String,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double
    ): ResultSlip =
        db.postgrest.rpc("submit_parent_result_slip", buildJsonObject {
            put("p_student_id", studentId)
            put("p_exam_name", examName)
            put("p_exam_date", examDate)
            put("p_subject", subject)
            put("p_score", score)
            put("p_max_score", maxScore)
        }).decodeList<ResultSlip>().single()

    suspend fun submitStaffResultSlip(
        studentId: String,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double,
        uploadedBy: String
    ): ResultSlip =
        db.from("result_slips").insert(
            ResultSlipInsert(
                studentId = studentId,
                examName = examName,
                examDate = examDate,
                subject = subject,
                score = score,
                maxScore = maxScore,
                uploadedBy = uploadedBy
            )
        ) { select() }.decodeSingle()

    suspend fun fetchMessages(studentId: String): List<ParentMessage> =
        db.postgrest.rpc("get_parent_messages", buildJsonObject {
            put("p_student_id", studentId)
        }).decodeList()

    suspend fun sendParentMessage(
        studentId: String,
        subject: String?,
        body: String
    ): ParentMessage =
        db.postgrest.rpc("send_parent_message", buildJsonObject {
            put("p_student_id", studentId)
            put("p_subject", subject)
            put("p_body", body)
        }).decodeList<ParentMessage>().single()
}

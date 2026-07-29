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

internal object PrivacyAdminDataSource {
    private val db get() = SupabaseClient.client

    // ---- PDPA: privacy notice ----

    suspend fun fetchPrivacyNotice(): PolicyDocument? =
        db.from("policy_documents").select {
            filter {
                eq("doc_type", "data_protection_notice")
                eq("is_current", true)
            }
            limit(1)
        }.decodeList<PolicyDocument>().firstOrNull()

    // ---- PDPA: consent ----

    /** Record consent through the shaped RPC. The database derives the actor,
     * method, current notice version, and timestamp. */
    suspend fun recordConsent(
        studentId: String,
        status: String,
        sourceNote: String? = null
    ) {
        db.postgrest.rpc("record_admin_consent", buildJsonObject {
            put("p_student_id", studentId)
            put("p_consent_type", "data_collection")
            put("p_status", status)
            sourceNote?.let { put("p_source_note", it) }
        })
    }

    /** Latest consent row per (student_id, consent_type) for one student. */
    suspend fun fetchCurrentConsent(studentId: String): List<ConsentRecord> =
        db.from("current_consent").select {
            filter { eq("student_id", studentId) }
        }.decodeList<ConsentRecord>()

    // ---- PDPA: erase / pseudonymise ----

    suspend fun anonymiseStudent(studentId: String) {
        throw IllegalStateException(
            "Pseudonymisation is available only in the secure admin web dashboard."
        )
    }

    suspend fun eraseStudent(studentId: String) {
        throw IllegalStateException(
            "Erasure is available only in the secure admin web dashboard."
        )
    }

    // ---- PDPA: subject-access export ----

    /** Returns the full personal-data bundle for a student as a JSON string. Auto-logs a
     * data_disclosures row server-side. */
    suspend fun exportStudentPersonalData(studentId: String): String {
        val result = db.postgrest.rpc(
            "export_student_personal_data",
            buildJsonObject { put("p_student_id", studentId) }
        )
        return result.data
    }

    // ---- PDPA: correction-request review queue ----

    suspend fun fetchPendingCorrectionRequests(): List<CorrectionRequest> =
        db.from("correction_requests").select {
            filter { eq("status", "pending") }
            order("created_at", Order.ASCENDING)
        }.decodeList<CorrectionRequest>()

    /** The database reviews, applies and logs the correction atomically. */
    suspend fun applyCorrectionRequest(request: CorrectionRequest) {
        reviewCorrectionRequest(request.id, "applied", null)
    }

    suspend fun rejectCorrectionRequest(request: CorrectionRequest, reviewNote: String?) {
        reviewCorrectionRequest(request.id, "rejected", reviewNote)
    }

    private suspend fun reviewCorrectionRequest(
        requestId: String,
        decision: String,
        reviewNote: String?
    ) {
        db.postgrest.rpc("review_correction_request", buildJsonObject {
            put("p_request_id", requestId)
            put("p_decision", decision)
            put("p_review_note", reviewNote)
        })
    }
}

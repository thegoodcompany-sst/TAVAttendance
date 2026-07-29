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

internal object MediaExportDataSource {
    private val db get() = SupabaseClient.client

    // ---- Feature flags (012) ----

    suspend fun fetchFeatureFlags(): Map<String, Boolean> =
        runCatching {
            db.from("feature_flags").select(Columns.list("key", "enabled"))
                .decodeList<FeatureFlag>()
                .associate { it.key to it.enabled }
        }.getOrDefault(emptyMap())  // fail closed → everything off

    // ---- Student photos (PROD-04, flag: student_photos) ----

    suspend fun uploadStudentPhoto(studentId: String, fileName: String, bytes: ByteArray): String {
        require(bytes.size <= 5 * 1024 * 1024) {
            "This photo is too large. Please choose an image under 5 MB."
        }
        val path = "$studentId/$fileName"
        SupabaseClient.client.storage.from("student-photos").upload(path, bytes) { upsert = true }
        db.from("students").update({ set("avatar_url", path) }) {
            filter { eq("id", studentId) }
        }
        return path
    }

    suspend fun signedStudentPhotoUrl(path: String): String =
        SupabaseClient.client.storage.from("student-photos")
            .createSignedUrl(path, 3600.seconds)

    // ---- Device tokens (PROD-02, flag: push_notifications) ----

    suspend fun registerDeviceToken(token: String, platform: String = "android") {
        db.postgrest.rpc("register_device_token", buildJsonObject {
            put("p_token", token)
            put("p_platform", platform)
        })
    }
}

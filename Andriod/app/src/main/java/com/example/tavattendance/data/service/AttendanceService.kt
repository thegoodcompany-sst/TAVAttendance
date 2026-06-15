package com.example.tavattendance.data.service

import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.*
import com.example.tavattendance.data.store.PendingAttendanceRecord
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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.*

object AttendanceService {
    private val db get() = SupabaseClient.client

    suspend fun fetchMyClasses(): List<TAVClass> =
        db.from("classes").select {
            filter { eq("is_active", true) }
            order("name", Order.ASCENDING)
        }.decodeList<TAVClass>()

    suspend fun createClass(cls: ClassInsert): TAVClass =
        db.from("classes").insert(cls) { select() }.decodeSingle<TAVClass>()

    suspend fun updateClass(id: String, cls: ClassInsert) {
        db.from("classes").update({
            set("name", cls.name)
            set("subject", cls.subject)
            set("level", cls.level)
            set("schedule_day", cls.scheduleDay)
            set("schedule_time", cls.scheduleTime)
            set("duration_minutes", cls.durationMinutes)
            set("is_active", cls.isActive)
        }) {
            filter { eq("id", id) }
        }
    }

    suspend fun deleteClass(id: String) {
        db.from("classes").update({ set("is_active", false) }) {
            filter { eq("id", id) }
        }
    }

    suspend fun fetchAllStudents(): List<Student> =
        db.from("students").select {
            filter { eq("is_active", true) }
            order("full_name", Order.ASCENDING)
        }.decodeList<Student>()

    suspend fun createStudent(student: StudentInsert): Student =
        db.from("students").insert(student) { select() }.decodeSingle<Student>()

    suspend fun updateStudent(id: String, student: StudentInsert) {
        db.from("students").update({
            set("full_name", student.fullName)
            set("school", student.school)
            set("year_of_study", student.yearOfStudy)
        }) {
            filter { eq("id", id) }
        }
    }

    suspend fun deactivateStudent(id: String) {
        db.from("students").update({ set("is_active", false) }) {
            filter { eq("id", id) }
        }
    }

    suspend fun fetchEnrollments(classId: String): List<Enrollment> =
        db.from("enrollments").select {
            filter {
                eq("class_id", classId)
                eq("is_active", true)
            }
        }.decodeList<Enrollment>()

    @Serializable
    private data class EnrollInsert(
        @SerialName("student_id") val studentId: String,
        @SerialName("class_id") val classId: String,
        @SerialName("is_active") val isActive: Boolean
    )

    suspend fun enrollStudent(studentId: String, classId: String) {
        db.from("enrollments").upsert(
            EnrollInsert(studentId = studentId, classId = classId, isActive = true)
        ) { onConflict = "student_id,class_id" }
    }

    suspend fun unenrollStudent(studentId: String, classId: String) {
        db.from("enrollments").update({ set("is_active", false) }) {
            filter {
                eq("student_id", studentId)
                eq("class_id", classId)
            }
        }
    }

    suspend fun fetchTutors(): List<Profile> =
        db.from("profiles").select {
            filter { eq("role", "tutor") }
            order("full_name", Order.ASCENDING)
        }.decodeList<Profile>()

    suspend fun fetchTutorAssignments(classId: String): List<TutorAssignment> =
        db.from("class_tutor_assignments")
            .select(Columns.list("id", "class_id", "tutor_id")) {
                filter { eq("class_id", classId) }
            }.decodeList<TutorAssignment>()

    @Serializable
    private data class AssignInsert(
        @SerialName("class_id") val classId: String,
        @SerialName("tutor_id") val tutorId: String
    )

    suspend fun assignTutor(tutorId: String, classId: String) {
        db.from("class_tutor_assignments").upsert(
            AssignInsert(classId = classId, tutorId = tutorId)
        ) { onConflict = "class_id,tutor_id" }
    }

    suspend fun unassignTutor(tutorId: String, classId: String) {
        db.from("class_tutor_assignments").delete {
            filter {
                eq("class_id", classId)
                eq("tutor_id", tutorId)
            }
        }
    }

    suspend fun fetchSessions(classId: String): List<Session> =
        db.from("sessions").select {
            filter { eq("class_id", classId) }
            order("session_date", Order.DESCENDING)
        }.decodeList<Session>()

    suspend fun getOrCreateSession(classId: String, date: String): Session {
        val existing = db.from("sessions").select {
            filter {
                eq("class_id", classId)
                eq("session_date", date)
            }
        }.decodeList<Session>()
        if (existing.isNotEmpty()) return existing.first()
        return db.from("sessions").insert(
            Session(
                id = UUID.randomUUID().toString(),
                classId = classId,
                sessionDate = date
            )
        ) { select() }.decodeSingle<Session>()
    }

    suspend fun fetchClass(id: String): TAVClass? =
        db.from("classes").select {
            filter { eq("id", id) }
        }.decodeList<TAVClass>().firstOrNull()

    suspend fun startSession(id: String) {
        db.from("sessions").update({
            set("started_at", java.time.Instant.now().toString())
        }) {
            filter { eq("id", id) }
        }
    }

    suspend fun endSession(id: String) {
        db.from("sessions").update({
            set("ended_at", java.time.Instant.now().toString())
        }) {
            filter { eq("id", id) }
        }
    }

    @Serializable
    private data class ResumePatch(
        // ALWAYS encode so null is sent as `"ended_at": null` even when encodeDefaults = false
        @kotlinx.serialization.EncodeDefault(kotlinx.serialization.EncodeDefault.Mode.ALWAYS)
        @SerialName("ended_at") val endedAt: String?
    )

    suspend fun resumeSession(id: String) {
        db.from("sessions").update(ResumePatch(null)) {
            filter { eq("id", id) }
        }
    }

    suspend fun fetchRoster(sessionId: String): List<RosterEntry> =
        db.postgrest.rpc("get_session_roster", buildJsonObject { put("p_session_id", sessionId) })
            .decodeList<RosterEntry>()

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

    suspend fun fetchKioskEntries(): List<KioskEntry> {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val classes = fetchMyClasses()
        val classMap = classes.associateBy { it.id }

        val sessionTuples = classes.map { cls ->
            cls.id to getOrCreateSession(classId = cls.id, date = today)
        }

        // PERF-02: fetch rosters in parallel instead of sequentially.
        // Each async block runs concurrently; awaitAll collects in declaration order,
        // preserving the (classId, session) association via the paired result.
        val rosterResults: List<Pair<Pair<String, Session>, List<RosterEntry>>> =
            coroutineScope {
                sessionTuples
                    .map { pair -> async { pair to fetchRoster(pair.second.id) } }
                    .awaitAll()
            }

        val entryMap = mutableMapOf<String, KioskEntry>()
        for ((classPair, roster) in rosterResults) {
            val (classId, session) = classPair
            val scheduleTime = classMap[classId]?.scheduleTime
            val slot = KioskSession(
                id = session.id,
                scheduleTime = scheduleTime,
                startedAt = session.startedAt
            )
            for (r in roster) {
                val existing = entryMap[r.studentId]
                val rMarkedAt = r.markedAt
                if (existing != null) {
                    val exMarkedAt = existing.markedAt
                    entryMap[r.studentId] = existing.copy(
                        sessions = existing.sessions + slot,
                        status = worstStatus(existing.status, r.status),
                        markedAt = if (rMarkedAt != null && (exMarkedAt == null || rMarkedAt > exMarkedAt)) rMarkedAt else exMarkedAt
                    )
                } else {
                    entryMap[r.studentId] = KioskEntry(
                        studentId = r.studentId,
                        fullName = r.fullName,
                        status = r.status,
                        sessions = listOf(slot),
                        markedAt = rMarkedAt
                    )
                }
            }
        }
        return entryMap.values.sortedBy { it.fullName }
    }

    // late > present > absent > excused
    fun worstStatus(a: AttendanceStatus?, b: AttendanceStatus?): AttendanceStatus? {
        val rank = mapOf(
            AttendanceStatus.late to 4,
            AttendanceStatus.present to 3,
            AttendanceStatus.absent to 2,
            AttendanceStatus.excused to 1
        )
        return when {
            a == null -> b
            b == null -> a
            (rank[b] ?: 0) > (rank[a] ?: 0) -> b
            else -> a
        }
    }

    suspend fun markKioskAttendance(entry: KioskEntry, status: AttendanceStatus) {
        for (session in entry.sessions) {
            markAttendance(sessionId = session.id, studentId = entry.studentId, status = status)
        }
    }

    suspend fun markKioskSignIn(entry: KioskEntry) {
        val now = Date()
        for (session in entry.sessions) {
            var status = AttendanceStatus.present
            if (session.startedAt != null) {
                val startedAt = runCatching {
                    java.time.Instant.parse(session.startedAt).let { Date(it.toEpochMilli()) }
                }.getOrNull()
                if (startedAt != null && now.after(startedAt)) {
                    status = AttendanceStatus.late
                }
            } else if (session.scheduleTime != null) {
                // Split on ":" taking first two parts — handles both "HH:mm" and "HH:mm:ss"
                val parts = session.scheduleTime.split(":").mapNotNull { it.toIntOrNull() }
                if (parts.size >= 2) {
                    val classCal = Calendar.getInstance()
                    classCal.set(Calendar.HOUR_OF_DAY, parts[0])
                    classCal.set(Calendar.MINUTE, parts[1])
                    classCal.set(Calendar.SECOND, 0)
                    classCal.set(Calendar.MILLISECOND, 0)
                    if (now.after(classCal.time)) {
                        status = AttendanceStatus.late
                    }
                }
            }
            markAttendance(sessionId = session.id, studentId = entry.studentId, status = status)
        }
    }

    suspend fun fetchStudentAttendanceHistory(
        studentId: String,
        limit: Int = 100,
        since: String? = null
    ): List<AttendanceHistoryRecord> =
        db.from("attendance_records")
            .select(Columns.raw("id, status, marked_at, session:sessions(session_date, class:classes(name))")) {
                filter {
                    eq("student_id", studentId)
                    if (since != null) gte("marked_at", since)
                }
                order("marked_at", Order.DESCENDING)
                limit(limit.toLong())
            }.decodeList<AttendanceHistoryRecord>()

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

    /** Insert an admin-attestation consent row for a student. notice_version is filled from the
     * current privacy notice when not supplied. */
    suspend fun recordConsent(
        studentId: String,
        status: String,
        noticeVersion: String? = null,
        sourceNote: String? = null
    ) {
        val version = noticeVersion ?: runCatching { fetchPrivacyNotice()?.version }.getOrNull()
        val grantedBy = SupabaseClient.client.auth.currentUserOrNull()?.id
        db.from("consent_records").insert(
            ConsentInsert(
                studentId = studentId,
                status = status,
                noticeVersion = version,
                grantedBy = grantedBy,
                sourceNote = sourceNote
            )
        )
    }

    /** Latest consent row per (student_id, consent_type) for one student. */
    suspend fun fetchCurrentConsent(studentId: String): List<ConsentRecord> =
        db.from("current_consent").select {
            filter { eq("student_id", studentId) }
        }.decodeList<ConsentRecord>()

    /** Full append-only consent ledger for one student (most recent first). */
    suspend fun fetchConsentHistory(studentId: String): List<ConsentRecord> =
        db.from("consent_records").select {
            filter { eq("student_id", studentId) }
            order("created_at", Order.DESCENDING)
        }.decodeList<ConsentRecord>()

    // ---- PDPA: erase / anonymise ----

    suspend fun anonymiseStudent(studentId: String) {
        db.postgrest.rpc("anonymise_student", buildJsonObject { put("p_student_id", studentId) })
    }

    suspend fun eraseStudent(studentId: String) {
        db.postgrest.rpc("erase_student", buildJsonObject { put("p_student_id", studentId) })
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

    /** Apply a correction: write the new value onto the student row, mark the request applied,
     * and log a correction_response disclosure. */
    suspend fun applyCorrectionRequest(request: CorrectionRequest) {
        // Only a known, safe allowlist of student columns may be corrected this way.
        val allowed = setOf("full_name", "school", "year_of_study")
        require(request.fieldName in allowed) {
            "Field '${request.fieldName}' cannot be auto-applied; correct it manually."
        }
        val newValue = request.requestedValue
        db.from("students").update({
            set(request.fieldName, newValue)
        }) { filter { eq("id", request.studentId) } }

        val reviewerId = SupabaseClient.client.auth.currentUserOrNull()?.id
        db.from("correction_requests").update({
            set("status", "applied")
            set("reviewed_by", reviewerId)
            set("reviewed_at", java.time.Instant.now().toString())
        }) { filter { eq("id", request.id) } }

        db.from("data_disclosures").insert(
            buildJsonObject {
                put("student_id", request.studentId)
                put("disclosure_type", "correction_response")
                put("disclosed_by", reviewerId)
            }
        )
    }

    suspend fun rejectCorrectionRequest(request: CorrectionRequest, reviewNote: String?) {
        val reviewerId = SupabaseClient.client.auth.currentUserOrNull()?.id
        db.from("correction_requests").update({
            set("status", "rejected")
            set("reviewed_by", reviewerId)
            set("reviewed_at", java.time.Instant.now().toString())
            set("review_note", reviewNote)
        }) { filter { eq("id", request.id) } }
    }

    // ---- PDPA: result-slip uploads (private bucket, "<student_id>/<filename>" path) ----

    /**
     * Upload an exam result slip to the private `result-slips` Storage bucket. The object is
     * always stored under "<student_id>/<filename>" so the parent-read Storage policy resolves.
     * Returns the storage path used.
     */
    suspend fun uploadResultSlip(studentId: String, fileName: String, bytes: ByteArray): String {
        val path = "$studentId/$fileName"
        SupabaseClient.client.storage.from("result-slips").upload(path, bytes) { upsert = true }
        return path
    }

    @Serializable
    private data class SyncRecord(
        @SerialName("session_id") val sessionId: String,
        @SerialName("student_id") val studentId: String,
        val status: String,
        val notes: String,
        @SerialName("client_mutation_id") val clientMutationId: String,
        @SerialName("marked_at") val markedAt: String
    )

    @Serializable
    private data class SyncParams(val records: List<SyncRecord>)

    suspend fun syncPending(records: List<PendingAttendanceRecord>): Pair<Int, Int> {
        val payload = records.map { r ->
            SyncRecord(
                sessionId = r.sessionId,
                studentId = r.studentId,
                status = r.status.name,
                notes = r.notes ?: "",
                clientMutationId = r.clientMutationId,
                markedAt = r.markedAt
            )
        }
        val paramsJson = Json.encodeToJsonElement(SyncParams(payload)) as JsonObject
        val result = db.postgrest.rpc("sync_attendance", paramsJson).decodeAs<Map<String, Int>>()
        return (result["synced"] ?: 0) to (result["skipped"] ?: 0)
    }
}

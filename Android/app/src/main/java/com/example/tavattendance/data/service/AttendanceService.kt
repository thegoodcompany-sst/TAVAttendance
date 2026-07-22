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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.*
import kotlin.time.Duration.Companion.seconds

object AttendanceService {
    private val db get() = SupabaseClient.client

    /** Shaped class projection for admins, assigned tutors, and recent
     * session-scoped substitutes. */
    suspend fun fetchMyClasses(): List<TAVClass> =
        db.postgrest.rpc("get_my_classes", buildJsonObject {}).decodeList()

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

    /** Parent-safe projection installed by migration 038. */
    suspend fun fetchParentChildren(): List<Student> =
        db.postgrest.rpc("get_parent_children", buildJsonObject {}).decodeList()

    suspend fun createStudentWithConsent(student: StudentInsert, sourceNote: String? = null): Student =
        db.postgrest.rpc("create_student_with_consent", buildJsonObject {
            put("p_full_name", student.fullName)
            student.school?.let { put("p_school", it) }
            student.yearOfStudy?.let { put("p_year_of_study", it) }
            sourceNote?.let { put("p_source_note", it) }
        }).decodeSingle<Student>()

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

    // ---- Student results (migration 023) ----

    /** RLS scopes rows to the caller: admins see all, tutors only students enrolled in
     * their assigned classes. */
    suspend fun fetchStudentResults(): List<StudentResult> =
        db.from("student_results").select().decodeList<StudentResult>()

    suspend fun upsertStudentResult(studentId: String, subject: ResultSubject, grade: String) {
        db.from("student_results").upsert(
            StudentResultUpsert(
                studentId = studentId,
                subject = subject.raw,
                grade = grade,
                updatedBy = db.auth.currentUserOrNull()?.id
            )
        ) { onConflict = "student_id,subject" }
    }

    suspend fun deleteStudentResult(studentId: String, subject: ResultSubject) {
        db.from("student_results").delete {
            filter {
                eq("student_id", studentId)
                eq("subject", subject.raw)
            }
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
        db.from("enrollments").update({
            set("is_active", false)
            set("unenrolled_at", java.time.Instant.now().toString())  // MAINT-04
        }) {
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
        @SerialName("tutor_id") val tutorId: String,
        // MAINT-05: optional end date (NULL = open-ended). Omitted when null.
        @SerialName("assigned_until") val assignedUntil: String? = null
    )

    suspend fun assignTutor(tutorId: String, classId: String, assignedUntil: String? = null) {
        db.from("class_tutor_assignments").upsert(
            AssignInsert(classId = classId, tutorId = tutorId, assignedUntil = assignedUntil)
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

    suspend fun getOrCreateTodaySession(classId: String): Session =
        db.postgrest.rpc("get_or_create_today_session", buildJsonObject {
            put("p_class_id", classId)
        }).decodeSingle<Session>()

    suspend fun fetchClass(id: String): TAVClass? =
        fetchMyClasses().firstOrNull { it.id == id }

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
        status: AttendanceStatus
    ) {
        db.postgrest.rpc("mark_retrospective_attendance", buildJsonObject {
            put("session_id", sessionId)
            put("student_id", studentId)
            put("status", status.name)
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

    suspend fun fetchKioskEntries(): List<KioskEntry> {
        // Day-aware: only create/show sessions for classes scheduled today, so opening the
        // kiosk on a non-tuition day doesn't spin up phantom sessions. Supports multiple
        // classes on the same day (e.g. Thu English + Thu Reading).
        val todayWeekday = weekdayName(Date())
        val classes = fetchMyClasses().filter {
            it.canOperateTodaySession && classMeetsToday(it, todayWeekday)
        }
        val classMap = classes.associateBy { it.id }

        val sessionTuples = classes.map { cls ->
            cls.id to getOrCreateTodaySession(classId = cls.id)
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
                        markedAt = rMarkedAt,
                        avatarUrl = r.avatarUrl  // PROD-04
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

    private val UUID_REGEX =
        Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    /**
     * Parses a kiosk QR payload (flag `qr_sign_in`) into a student UUID string.
     * Tolerates surrounding whitespace (some QR generators append a trailing newline)
     * and normalises to lowercase for matching; anything that isn't a bare UUID
     * (URLs, garbage) is rejected. Mirrors iOS `studentId(fromQRPayload:)`.
     */
    fun studentIdFromQrPayload(payload: String): String? {
        val trimmed = payload.trim()
        return if (UUID_REGEX.matches(trimmed)) trimmed.lowercase() else null
    }

    // ---- Day-of-week scheduling ----

    /** English full weekday name ("Monday".."Sunday") for the given date. */
    fun weekdayName(date: Date): String =
        SimpleDateFormat("EEEE", Locale.ENGLISH).format(date)

    /**
     * Whether a class meets on [weekday] (an English full weekday name). The class's
     * recurrence_rule BYDAY wins when present; otherwise schedule_day is matched; a class
     * with neither set is treated as ad-hoc and always shown.
     */
    fun classMeetsToday(cls: TAVClass, weekday: String): Boolean {
        val rule = cls.recurrenceRule
        if (rule != null) {
            val codes = bydayCodes(rule)
            if (!codes.isNullOrEmpty()) return codes.contains(weekdayCode(weekday))
        }
        val day = cls.scheduleDay
        if (!day.isNullOrEmpty()) return day.equals(weekday, ignoreCase = true)
        return true
    }

    private fun weekdayCode(weekday: String): String = when (weekday.lowercase()) {
        "monday" -> "MO"
        "tuesday" -> "TU"
        "wednesday" -> "WE"
        "thursday" -> "TH"
        "friday" -> "FR"
        "saturday" -> "SA"
        "sunday" -> "SU"
        else -> ""
    }

    private fun bydayCodes(rule: String): List<String>? {
        for (part in rule.split(";")) {
            val kv = part.split("=", limit = 2)
            if (kv.size == 2 && kv[0].uppercase() == "BYDAY") {
                return kv[1].split(",").map { it.trim().uppercase() }
            }
        }
        return null
    }

    // ---- Study Space (internal-only; migration 015) ----

    /** The singleton internal Study Space (drop-in room) class. Attendance here is
     * Present / Not Here only and is EXCLUDED from all reports & parent views. */
    const val STUDY_SPACE_CLASS_ID = "57000000-0000-0000-0000-000000000001"

    /** Loads today's Study Space session (creating it on first use) and the roster of ALL
     * active students with their current Present/Not-Here status for it. */
    suspend fun loadStudySpace(): Pair<Session, List<RosterEntry>> {
        val session = getOrCreateTodaySession(classId = STUDY_SPACE_CLASS_ID)
        val roster = db.postgrest
            .rpc("get_study_space_roster", buildJsonObject { put("p_session_id", session.id) })
            .decodeList<RosterEntry>()
        return session to roster
    }

    suspend fun markKioskAttendance(entry: KioskEntry, status: AttendanceStatus) {
        for (session in entry.sessions) {
            markAttendance(sessionId = session.id, studentId = entry.studentId, status = status)
        }
    }

    suspend fun markKioskSignIn(entry: KioskEntry) {
        val now = Date()
        for (session in entry.sessions) {
            markAttendance(
                sessionId = session.id,
                studentId = entry.studentId,
                status = signInStatus(session, now)
            )
        }
    }

    /** Present, or late when the session has started (or its scheduled time has passed). */
    fun signInStatus(session: KioskSession, now: Date): AttendanceStatus {
        val startedAt = session.startedAt?.let {
            runCatching { java.time.Instant.parse(it).let { i -> Date(i.toEpochMilli()) } }.getOrNull()
        }
        if (startedAt != null) {
            if (now.after(startedAt)) return AttendanceStatus.late
        } else if (session.scheduleTime != null) {
            // Falls through here both when startedAt is null AND when it failed to parse —
            // an unparsable startedAt must not silently default to Present.
            // Split on ":" taking first two parts — handles both "HH:mm" and "HH:mm:ss"
            val parts = session.scheduleTime.split(":").mapNotNull { it.toIntOrNull() }
            if (parts.size >= 2) {
                val classCal = Calendar.getInstance()
                classCal.set(Calendar.HOUR_OF_DAY, parts[0])
                classCal.set(Calendar.MINUTE, parts[1])
                classCal.set(Calendar.SECOND, 0)
                classCal.set(Calendar.MILLISECOND, 0)
                if (now.after(classCal.time)) return AttendanceStatus.late
            }
        }
        return AttendanceStatus.present
    }

    suspend fun fetchStudentAttendanceHistory(
        studentId: String,
        limit: Int = 100,
        since: String? = null
    ): List<AttendanceHistoryRecord> =
        db.from("attendance_records")
            // QA-05: filter the window by session_date (the real class date), not
            // marked_at; `!inner` makes the embedded filter apply to the top-level rows.
            .select(Columns.raw("id, status, marked_at, session:sessions!inner(session_date, class:classes!inner(name))")) {
                filter {
                    eq("student_id", studentId)
                    // Study Space attendance is internal-only — never show it in student history.
                    eq("session.class.is_study_space", false)
                    if (since != null) gte("session.session_date", since)
                }
                order("marked_at", Order.DESCENDING)
                limit(limit.toLong())
            }.decodeList<AttendanceHistoryRecord>()

    /** Parent-safe attendance projection with no staff notes, actor IDs, or mutation IDs. */
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

    // ---- Safely home (migration 030, flag: push_notifications) ----

    /** Today's dismissals visible to the caller (RLS: parents see own children only). */
    suspend fun fetchTodayDismissals(): List<Dismissal> =
        db.postgrest.rpc("get_parent_dismissals", buildJsonObject {}).decodeList()

    /** Dismissals still awaiting a parent's safely-home confirmation. */
    fun awaitingSafelyHome(dismissals: List<Dismissal>): List<Dismissal> =
        dismissals.filter { it.safelyHomeAt == null && it.dismissedAt != null }

    /** Parent-only, once-only: sets safely_home_at on the child's dismissal row.
     * Server enforces ownership and immutability (mark_safely_home, migration 030). */
    suspend fun markSafelyHome(dismissalId: String) {
        db.postgrest.rpc("mark_safely_home", buildJsonObject { put("p_dismissal_id", dismissalId) })
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

    /** synced, skipped (newer server record won), blocked_ended_session (session already ended — migration 016). */
    data class SyncResult(val synced: Int, val skipped: Int, val blockedEndedSession: Int)

    suspend fun syncPending(records: List<PendingAttendanceRecord>): SyncResult {
        val currentUserId = db.auth.currentUserOrNull()?.id
            ?: throw SecurityException("Cannot sync attendance without an authenticated user")
        if (!pendingRecordsBelongToOwner(records, currentUserId)) {
            throw SecurityException("Pending attendance belongs to a different account")
        }
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
        return SyncResult(
            synced = result["synced"] ?: 0,
            skipped = result["skipped"] ?: 0,
            blockedEndedSession = result["blocked_ended_session"] ?: 0
        )
    }
}

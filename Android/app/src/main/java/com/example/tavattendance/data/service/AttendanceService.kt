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
import kotlin.time.Duration.Companion.seconds

object AttendanceService {
    private val db get() = SupabaseClient.client

    suspend fun fetchMyClasses(): List<TAVClass> =
        db.from("classes").select {
            // Excludes the internal Study Space class (migration 015) so it never appears
            // in the tutor/admin class list or the tuition kiosk grid.
            filter {
                eq("is_active", true)
                eq("is_study_space", false)
            }
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

    suspend fun getOrCreateSession(classId: String, date: String): Session {
        val existing = db.from("sessions").select {
            filter {
                eq("class_id", classId)
                eq("session_date", date)
            }
        }.decodeList<Session>()
        if (existing.isNotEmpty()) return existing.first()
        return try {
            db.from("sessions").insert(
                Session(
                    id = UUID.randomUUID().toString(),
                    classId = classId,
                    sessionDate = date
                )
            ) { select() }.decodeSingle<Session>()
        } catch (e: Exception) {
            // Two kiosks/tutors opening the same class at once can both lose the initial
            // select race and then collide on the sessions(class_id, session_date) unique
            // constraint (001_schema.sql). Re-select instead of failing outright.
            // ponytail: catch-and-reselect instead of an upsert, since an upsert would need to
            // send `id` in the payload and risk overwriting the winner's id on conflict.
            db.from("sessions").select {
                filter {
                    eq("class_id", classId)
                    eq("session_date", date)
                }
            }.decodeList<Session>().firstOrNull() ?: throw e
        }
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

    @Serializable
    private data class NotesPatch(
        // ALWAYS encode so an emptied note is sent as `"notes": null` (SQL NULL)
        @kotlinx.serialization.EncodeDefault(kotlinx.serialization.EncodeDefault.Mode.ALWAYS)
        @SerialName("notes") val notes: String?
    )

    suspend fun fetchSessionNotes(id: String): String? =
        db.from("sessions").select {
            filter { eq("id", id) }
        }.decodeList<Session>().firstOrNull()?.notes

    /** Saves the tutor's free-text note on a session (flag `session_notes`). Empty note → SQL NULL. */
    suspend fun updateSessionNotes(id: String, notes: String?) {
        db.from("sessions").update(NotesPatch(notes)) {
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
        // Day-aware: only create/show sessions for classes scheduled today, so opening the
        // kiosk on a non-tuition day doesn't spin up phantom sessions. Supports multiple
        // classes on the same day (e.g. Thu English + Thu Reading).
        val todayWeekday = weekdayName(Date())
        val classes = fetchMyClasses().filter { classMeetsToday(it, todayWeekday) }
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
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val session = getOrCreateSession(classId = STUDY_SPACE_CLASS_ID, date = today)
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

    // ---- PDPA: erase / anonymise ----

    suspend fun anonymiseStudent(studentId: String) {
        removeStudentStorage(studentId)
        db.postgrest.rpc("anonymise_student", buildJsonObject { put("p_student_id", studentId) })
    }

    suspend fun eraseStudent(studentId: String) {
        removeStudentStorage(studentId)
        db.postgrest.rpc("erase_student", buildJsonObject { put("p_student_id", studentId) })
    }

    /** PostgreSQL cascades cannot remove Storage objects. Delete every object in
     * both student-scoped folders before erasing the database identity. */
    private suspend fun removeStudentStorage(studentId: String) {
        for (bucketName in listOf("result-slips", "student-photos")) {
            val bucket = db.storage.from(bucketName)
            for (folder in setOf(studentId.lowercase(), studentId.uppercase())) {
                while (true) {
                    val objects = bucket.list(folder) {
                        limit = 100
                        offset = 0
                    }
                    val paths = objects.filter { it.id != null }.map { "$folder/${it.name}" }
                    if (paths.isNotEmpty()) bucket.delete(paths)
                    if (objects.size < 100 || paths.isEmpty()) break
                }
            }
        }
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
        // SP-09: reject oversized uploads before hitting Storage (limit 10 MB).
        require(bytes.size <= 10 * 1024 * 1024) {
            "This file is too large. Please choose a result slip under 10 MB."
        }
        val path = "$studentId/$fileName"
        SupabaseClient.client.storage.from("result-slips").upload(path, bytes) { upsert = true }
        return path
    }

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

    @Serializable
    private data class TokenInsert(
        @SerialName("user_id") val userId: String,
        val token: String,
        val platform: String
    )

    suspend fun registerDeviceToken(token: String, platform: String = "android") {
        val userId = db.auth.currentUserOrNull()?.id ?: return
        db.from("device_tokens").upsert(
            TokenInsert(userId = userId, token = token, platform = platform)
        ) { onConflict = "token" }
    }

    // ---- Safely home (migration 030, flag: push_notifications) ----

    /** Today's dismissals visible to the caller (RLS: parents see own children only). */
    suspend fun fetchTodayDismissals(): List<Dismissal> {
        val todayStart = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()) + "T00:00:00"
        return db.from("dismissals").select {
            filter { gte("dismissed_at", todayStart) }
            order("dismissed_at", Order.DESCENDING)
        }.decodeList<Dismissal>()
    }

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

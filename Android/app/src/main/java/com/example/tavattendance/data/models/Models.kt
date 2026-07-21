package com.example.tavattendance.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.ZoneId

@Serializable
data class Profile(
    val id: String,
    @SerialName("full_name") val fullName: String,
    val role: String,
    val phone: String? = null
)

@Serializable
data class TAVClass(
    val id: String,
    val name: String,
    val subject: String? = null,
    val level: String? = null,
    @SerialName("schedule_day") val scheduleDay: String? = null,
    @SerialName("schedule_time") val scheduleTime: String? = null,
    @SerialName("duration_minutes") val durationMinutes: Int = 60,
    @SerialName("is_active") val isActive: Boolean = true,
    // RFC 5545 RRULE, e.g. "FREQ=WEEKLY;BYDAY=MO,TH" — used for day-aware kiosk filtering.
    @SerialName("recurrence_rule") val recurrenceRule: String? = null,
    // Migration 015: the internal Study Space (drop-in) class. Default false for
    // decode safety against prod schema drift.
    @SerialName("is_study_space") val isStudySpace: Boolean = false
)

@Serializable
data class Student(
    val id: String,
    @SerialName("full_name") val fullName: String,
    val school: String? = null,
    @SerialName("year_of_study") val yearOfStudy: String? = null,
    @SerialName("is_active") val isActive: Boolean = true,
    // PROD-04: storage path to the student's photo; shown only when the
    // student_photos feature flag is on.
    @SerialName("avatar_url") val avatarUrl: String? = null
) {
    val isPrimaryLevel: Boolean? get() = classifyPrimaryLevel(yearOfStudy)
}

// The two canonical subjects (migration 023). The DB stores the raw values
// 'Math' / 'English'; free-text classes.subject is mapped on via normalizing().
enum class ResultSubject(val raw: String, val displayName: String) {
    MATH("Math", "Mathematics"),
    ENGLISH("English", "English");

    companion object {
        fun fromRaw(raw: String?): ResultSubject? = entries.firstOrNull { it.raw == raw }

        /** Maps free-text classes.subject ("Math", "Mathematics ", "english"…) onto the
         * two canonical subjects; null for anything else. */
        fun normalizing(raw: String?): ResultSubject? {
            val s = (raw ?: "").trim().lowercase()
            return when {
                s.startsWith("math") -> MATH
                s.startsWith("eng") -> ENGLISH
                else -> null
            }
        }
    }
}

// PSLE Achievement Levels (primary) vs O-Level grades (secondary), migration 023.
object GradeBands {
    val primary = listOf("AL1", "AL2", "AL3", "AL4", "AL5", "AL6", "AL7", "AL8")
    val secondary = listOf("A1", "A2", "B3", "B4", "C5", "C6", "D7", "E8", "F9")
}

/** Classifies free-text year_of_study ("P5", "sec 2", "3") into primary/secondary to pick
 * the grade band; null when ambiguous (grade picker then shows both bands). */
fun classifyPrimaryLevel(yearOfStudy: String?): Boolean? {
    val s = (yearOfStudy ?: "").trim().lowercase()
    return when {
        s.startsWith("p") || s.contains("pri") -> true
        s.startsWith("s") || s.contains("sec") -> false
        else -> null
    }
}

@Serializable
data class StudentResult(
    val id: String,
    @SerialName("student_id") val studentId: String,
    val subject: String,
    val grade: String
)

@Serializable
data class StudentResultUpsert(
    @SerialName("student_id") val studentId: String,
    val subject: String,
    val grade: String,
    @SerialName("updated_by") val updatedBy: String? = null
)

@Serializable
data class Session(
    val id: String,
    @SerialName("class_id") val classId: String,
    @SerialName("session_date") val sessionDate: String,
    val topic: String? = null,
    val notes: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("sub_tutor_id") val subTutorId: String? = null
)

/** Pure client-side gates for migration 037's historical-session workflow. */
object RetrospectiveSessionRules {
    private val singapore = ZoneId.of("Asia/Singapore")

    fun today(): LocalDate = LocalDate.now(singapore)

    fun isPastDate(date: String, today: LocalDate = today()): Boolean =
        runCatching { LocalDate.parse(date).isBefore(today) }.getOrDefault(false)

    fun existingSession(date: String, sessions: List<Session>): Session? =
        sessions.firstOrNull { it.sessionDate == date }

    fun editorEnabled(
        session: Session,
        flagEnabled: Boolean,
        today: LocalDate = today()
    ): Boolean = flagEnabled && isPastDate(session.sessionDate, today)
}

@Serializable
enum class AttendanceStatus { present, absent, late, excused }

@Serializable
data class AttendanceInsert(
    @SerialName("session_id") val sessionId: String,
    @SerialName("student_id") val studentId: String,
    val status: AttendanceStatus,
    val notes: String? = null,
    @SerialName("client_mutation_id") val clientMutationId: String
)

@Serializable
data class RosterEntry(
    @SerialName("student_id") val studentId: String,
    @SerialName("full_name") val fullName: String,
    @SerialName("attendance_id") val attendanceId: String? = null,
    val status: AttendanceStatus? = null,
    @SerialName("marked_at") val markedAt: String? = null,
    val notes: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null  // PROD-04
)

@Serializable
data class ClassInsert(
    val name: String,
    val subject: String? = null,
    val level: String? = null,
    @SerialName("schedule_day") val scheduleDay: String? = null,
    @SerialName("schedule_time") val scheduleTime: String? = null,
    @SerialName("duration_minutes") val durationMinutes: Int = 60,
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class StudentInsert(
    @SerialName("full_name") val fullName: String,
    val school: String? = null,
    @SerialName("year_of_study") val yearOfStudy: String? = null
)

@Serializable
data class Enrollment(
    val id: String,
    @SerialName("student_id") val studentId: String,
    @SerialName("class_id") val classId: String,
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class TutorAssignment(
    val id: String,
    @SerialName("class_id") val classId: String,
    @SerialName("tutor_id") val tutorId: String
)

// Kiosk models (not stored in DB, built client-side)

data class KioskSession(
    val id: String,
    val scheduleTime: String?,
    val startedAt: String?
)

data class KioskEntry(
    val studentId: String,
    val fullName: String,
    var status: AttendanceStatus?,
    var sessions: List<KioskSession>,
    var markedAt: String? = null,
    var avatarUrl: String? = null  // PROD-04
) {
    val isAttending: Boolean get() = status == AttendanceStatus.present || status == AttendanceStatus.late
}

@Serializable
data class FeatureFlag(
    val key: String,
    val enabled: Boolean
)

// ---- PDPA models ----

@Serializable
data class PolicyDocument(
    val id: String,
    @SerialName("doc_type") val docType: String,
    val version: String,
    val title: String,
    val body: String,
    @SerialName("is_current") val isCurrent: Boolean = true,
    @SerialName("published_at") val publishedAt: String? = null
)

@Serializable
data class ConsentRecord(
    @SerialName("student_id") val studentId: String,
    @SerialName("consent_type") val consentType: String,
    val status: String,
    val method: String,
    @SerialName("notice_version") val noticeVersion: String? = null,
    @SerialName("granted_by") val grantedBy: String? = null,
    @SerialName("parent_id") val parentId: String? = null,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
data class ConsentInsert(
    @SerialName("student_id") val studentId: String,
    @SerialName("consent_type") val consentType: String = "data_collection",
    val status: String,
    val method: String = "admin_attestation",
    @SerialName("notice_version") val noticeVersion: String? = null,
    @SerialName("granted_by") val grantedBy: String? = null,
    @SerialName("source_note") val sourceNote: String? = null
)

@Serializable
data class CorrectionRequest(
    val id: String,
    @SerialName("student_id") val studentId: String,
    @SerialName("requested_by") val requestedBy: String? = null,
    @SerialName("field_name") val fieldName: String,
    @SerialName("current_value") val currentValue: String? = null,
    @SerialName("requested_value") val requestedValue: String? = null,
    val status: String,
    @SerialName("review_note") val reviewNote: String? = null,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
data class AttendanceHistoryRecord(
    val id: String,
    val status: AttendanceStatus,
    @SerialName("marked_at") val markedAt: String? = null,
    val session: SessionSummary
) {
    @Serializable
    data class SessionSummary(
        @SerialName("session_date") val sessionDate: String,
        @SerialName("class") val cls: ClassSummary
    ) {
        @Serializable
        data class ClassSummary(val name: String)
    }
}

/** A dismissal event (Phase 3 `dismissals` table). Parents read their own child's
 * rows (RLS, migration 011) and confirm safely-home via the mark_safely_home RPC
 * (migration 030). */
@Serializable
data class Dismissal(
    val id: String,
    @SerialName("session_id") val sessionId: String? = null,
    @SerialName("student_id") val studentId: String? = null,
    @SerialName("dismissed_at") val dismissedAt: String? = null,
    @SerialName("safely_home_at") val safelyHomeAt: String? = null
)

// ---- Parent portal Phase 2: result slips + messages ----

@Serializable
data class ResultSlip(
    val id: String,
    @SerialName("student_id") val studentId: String,
    @SerialName("exam_name") val examName: String? = null,
    @SerialName("exam_date") val examDate: String? = null,
    val subject: String? = null,
    val score: Double? = null,
    @SerialName("max_score") val maxScore: Double? = null,
    @SerialName("uploaded_at") val uploadedAt: String? = null,
    @SerialName("acknowledged_at") val acknowledgedAt: String? = null
) {
    val isAcknowledged: Boolean get() = acknowledgedAt != null

    val fractionDisplay: String? get() {
        val s = score ?: return null
        val m = maxScore ?: return null
        val sStr = if (s == s.toLong().toDouble()) s.toLong().toString() else s.toString()
        val mStr = if (m == m.toLong().toDouble()) m.toLong().toString() else m.toString()
        return "$sStr / $mStr"
    }
}

@Serializable
data class ResultSlipInsert(
    @SerialName("student_id") val studentId: String,
    @SerialName("exam_name") val examName: String,
    @SerialName("exam_date") val examDate: String,
    val subject: String,
    val score: Double,
    @SerialName("max_score") val maxScore: Double,
    @SerialName("uploaded_by") val uploadedBy: String
)

/** Client-side validation for text-only result-slip inserts. */
object ResultSlipInputValidation {
    enum class Failure {
        EMPTY_EXAM_NAME,
        INVALID_SCORE,
        INVALID_MAX_SCORE,
        SCORE_EXCEEDS_MAX;

        val message: String get() = when (this) {
            EMPTY_EXAM_NAME -> "Exam name is required."
            INVALID_SCORE -> "Score must be zero or greater."
            INVALID_MAX_SCORE -> "Maximum score must be greater than zero."
            SCORE_EXCEEDS_MAX -> "Score cannot exceed the maximum."
        }
    }

    fun validate(examName: String, score: Double?, maxScore: Double?): Failure? {
        if (examName.trim().isEmpty()) return Failure.EMPTY_EXAM_NAME
        if (score == null || !score.isFinite() || score < 0) return Failure.INVALID_SCORE
        if (maxScore == null || !maxScore.isFinite() || maxScore <= 0) return Failure.INVALID_MAX_SCORE
        if (score > maxScore) return Failure.SCORE_EXCEEDS_MAX
        return null
    }
}

@Serializable
data class ParentMessage(
    val id: String,
    @SerialName("sender_id") val senderId: String? = null,
    @SerialName("recipient_id") val recipientId: String? = null,
    @SerialName("student_id") val studentId: String? = null,
    val subject: String? = null,
    val body: String,
    @SerialName("sent_at") val sentAt: String? = null,
    @SerialName("read_at") val readAt: String? = null
) {
    /** Parent-originated when recipient is null (centre is the implicit recipient). */
    val isFromParent: Boolean get() = recipientId == null
}

@Serializable
data class ParentMessageInsert(
    @SerialName("sender_id") val senderId: String,
    @SerialName("student_id") val studentId: String,
    @SerialName("recipient_id") val recipientId: String? = null,
    val subject: String? = null,
    val body: String
)

package com.example.tavattendance.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

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
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class Student(
    val id: String,
    @SerialName("full_name") val fullName: String,
    val school: String? = null,
    @SerialName("year_of_study") val yearOfStudy: String? = null,
    @SerialName("is_active") val isActive: Boolean = true
)

@Serializable
data class Session(
    val id: String,
    @SerialName("class_id") val classId: String,
    @SerialName("session_date") val sessionDate: String,
    val topic: String? = null,
    val notes: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null
)

@Serializable
enum class AttendanceStatus { present, absent, late, excused }

@Serializable
data class AttendanceRecord(
    val id: String? = null,
    @SerialName("session_id") val sessionId: String,
    @SerialName("student_id") val studentId: String,
    val status: AttendanceStatus,
    @SerialName("marked_by") val markedBy: String? = null,
    @SerialName("marked_at") val markedAt: String? = null,
    val notes: String? = null,
    @SerialName("client_mutation_id") val clientMutationId: String
)

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
    val notes: String? = null
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
    var markedAt: String? = null
) {
    val isAttending: Boolean get() = status == AttendanceStatus.present || status == AttendanceStatus.late
}

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

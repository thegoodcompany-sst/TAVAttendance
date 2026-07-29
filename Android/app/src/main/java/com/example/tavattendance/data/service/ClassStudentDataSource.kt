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

internal object ClassStudentDataSource {
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
}

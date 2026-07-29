package com.example.tavattendance.data.service

import com.example.tavattendance.data.models.*
import com.example.tavattendance.data.store.PendingAttendanceRecord
import java.util.Date

/**
 * Sole caller-facing attendance facade. Implementation lives in package-internal
 * domain data sources; signatures stay stable for all call sites and tests.
 */
object AttendanceService {
    data class SyncResult(val synced: Int, val skipped: Int, val blockedEndedSession: Int)

    suspend fun fetchMyClasses(): List<TAVClass> =
        ClassStudentDataSource.fetchMyClasses()

    suspend fun createClass(cls: ClassInsert): TAVClass =
        ClassStudentDataSource.createClass(cls)

    suspend fun updateClass(id: String, cls: ClassInsert) =
        ClassStudentDataSource.updateClass(id, cls)

    suspend fun deleteClass(id: String) =
        ClassStudentDataSource.deleteClass(id)

    suspend fun fetchAllStudents(): List<Student> =
        ClassStudentDataSource.fetchAllStudents()

    suspend fun fetchParentChildren(): List<Student> =
        ClassStudentDataSource.fetchParentChildren()

    suspend fun createStudentWithConsent(student: StudentInsert, sourceNote: String? = null): Student =
        ClassStudentDataSource.createStudentWithConsent(student, sourceNote)

    suspend fun updateStudent(id: String, student: StudentInsert) =
        ClassStudentDataSource.updateStudent(id, student)

    suspend fun deactivateStudent(id: String) =
        ClassStudentDataSource.deactivateStudent(id)

    suspend fun fetchStudentResults(): List<StudentResult> =
        ClassStudentDataSource.fetchStudentResults()

    suspend fun upsertStudentResult(studentId: String, subject: ResultSubject, grade: String) =
        ClassStudentDataSource.upsertStudentResult(studentId, subject, grade)

    suspend fun deleteStudentResult(studentId: String, subject: ResultSubject) =
        ClassStudentDataSource.deleteStudentResult(studentId, subject)

    suspend fun fetchEnrollments(classId: String): List<Enrollment> =
        ClassStudentDataSource.fetchEnrollments(classId)

    suspend fun enrollStudent(studentId: String, classId: String) =
        ClassStudentDataSource.enrollStudent(studentId, classId)

    suspend fun unenrollStudent(studentId: String, classId: String) =
        ClassStudentDataSource.unenrollStudent(studentId, classId)

    suspend fun fetchTutors(): List<Profile> =
        ClassStudentDataSource.fetchTutors()

    suspend fun fetchTutorAssignments(classId: String): List<TutorAssignment> =
        ClassStudentDataSource.fetchTutorAssignments(classId)

    suspend fun assignTutor(tutorId: String, classId: String, assignedUntil: String? = null) =
        ClassStudentDataSource.assignTutor(tutorId, classId, assignedUntil)

    suspend fun unassignTutor(tutorId: String, classId: String) =
        ClassStudentDataSource.unassignTutor(tutorId, classId)

    suspend fun fetchSessions(classId: String): List<Session> =
        SessionAttendanceDataSource.fetchSessions(classId)

    suspend fun getOrCreateTodaySession(classId: String): Session =
        SessionAttendanceDataSource.getOrCreateTodaySession(classId)

    suspend fun fetchClass(id: String): TAVClass? =
        SessionAttendanceDataSource.fetchClass(id)

    suspend fun startSession(id: String) =
        SessionAttendanceDataSource.startSession(id)

    suspend fun endSession(id: String) =
        SessionAttendanceDataSource.endSession(id)

    suspend fun createRetrospectiveSession(
        classId: String,
        sessionDate: String,
        topic: String?,
        notes: String?,
        subTutorId: String?
    ): Session = db.postgrest.rpc("create_retrospective_session", buildJsonObject =
        SessionAttendanceDataSource.createRetrospectiveSession(classId, sessionDate, topic, notes, subTutorId)

    suspend fun updateRetrospectiveSession(
        sessionId: String,
        topic: String?,
        notes: String?,
        subTutorId: String?
    ): Session = db.postgrest.rpc("update_retrospective_session", buildJsonObject =
        SessionAttendanceDataSource.updateRetrospectiveSession(sessionId, topic, notes, subTutorId)

    suspend fun fetchSessionNotes(id: String): String? =
        SessionAttendanceDataSource.fetchSessionNotes(id)

    suspend fun fetchSession(id: String): Session? =
        SessionAttendanceDataSource.fetchSession(id)

    suspend fun updateSessionNotes(id: String, notes: String?) =
        SessionAttendanceDataSource.updateSessionNotes(id, notes)

    suspend fun fetchRoster(sessionId: String): List<RosterEntry> =
        SessionAttendanceDataSource.fetchRoster(sessionId)

    suspend fun fetchRetrospectiveRoster(sessionId: String): List<RosterEntry> =
        SessionAttendanceDataSource.fetchRetrospectiveRoster(sessionId)

    suspend fun markRetrospectiveAttendance(
        sessionId: String,
        studentId: String,
        status: AttendanceStatus
    ) =
        SessionAttendanceDataSource.markRetrospectiveAttendance(sessionId, studentId, status)

    suspend fun markAttendance(
        sessionId: String, studentId: String, status: AttendanceStatus, notes: String? = null
    ) =
        SessionAttendanceDataSource.markAttendance(sessionId, studentId, status, notes)

    suspend fun fetchKioskEntries(): List<KioskEntry> =
        KioskAttendanceDataSource.fetchKioskEntries()

    fun worstStatus(a: AttendanceStatus?, b: AttendanceStatus?): AttendanceStatus? =
        KioskAttendanceDataSource.worstStatus(a, b)

    fun studentIdFromQrPayload(payload: String): String? =
        KioskAttendanceDataSource.studentIdFromQrPayload(payload)

    fun weekdayName(date: Date): String =
        KioskAttendanceDataSource.weekdayName(date)

    fun classMeetsToday(cls: TAVClass, weekday: String): Boolean =
        KioskAttendanceDataSource.classMeetsToday(cls, weekday)

    suspend fun loadStudySpace(): Pair<Session, List<RosterEntry>> =
        KioskAttendanceDataSource.loadStudySpace()

    suspend fun markKioskAttendance(entry: KioskEntry, status: AttendanceStatus) =
        KioskAttendanceDataSource.markKioskAttendance(entry, status)

    suspend fun markKioskSignIn(entry: KioskEntry) =
        KioskAttendanceDataSource.markKioskSignIn(entry)

    fun signInStatus(session: KioskSession, now: Date): AttendanceStatus =
        KioskAttendanceDataSource.signInStatus(session, now)

    suspend fun fetchStudentAttendanceHistory(
        studentId: String,
        limit: Int = 100,
        since: String? = null
    ): List<AttendanceHistoryRecord> =
        SessionAttendanceDataSource.fetchStudentAttendanceHistory(studentId, limit, since)

    suspend fun fetchParentAttendanceHistory(
        studentId: String,
        limit: Int = 100,
        since: String? = null
    ): List<AttendanceHistoryRecord> =
        ParentPortalDataSource.fetchParentAttendanceHistory(studentId, limit, since)

    suspend fun fetchPrivacyNotice(): PolicyDocument? =
        PrivacyAdminDataSource.fetchPrivacyNotice()

    suspend fun recordConsent(
        studentId: String,
        status: String,
        sourceNote: String? = null
    ) =
        PrivacyAdminDataSource.recordConsent(studentId, status, sourceNote)

    suspend fun fetchCurrentConsent(studentId: String): List<ConsentRecord> =
        PrivacyAdminDataSource.fetchCurrentConsent(studentId)

    suspend fun anonymiseStudent(studentId: String) =
        PrivacyAdminDataSource.anonymiseStudent(studentId)

    suspend fun eraseStudent(studentId: String) =
        PrivacyAdminDataSource.eraseStudent(studentId)

    suspend fun exportStudentPersonalData(studentId: String): String =
        PrivacyAdminDataSource.exportStudentPersonalData(studentId)

    suspend fun fetchPendingCorrectionRequests(): List<CorrectionRequest> =
        PrivacyAdminDataSource.fetchPendingCorrectionRequests()

    suspend fun applyCorrectionRequest(request: CorrectionRequest) =
        PrivacyAdminDataSource.applyCorrectionRequest(request)

    suspend fun rejectCorrectionRequest(request: CorrectionRequest, reviewNote: String?) =
        PrivacyAdminDataSource.rejectCorrectionRequest(request, reviewNote)

    suspend fun fetchResultSlips(studentId: String): List<ResultSlip> =
        ParentPortalDataSource.fetchResultSlips(studentId)

    suspend fun fetchStaffResultSlips(studentId: String): List<ResultSlip> =
        ParentPortalDataSource.fetchStaffResultSlips(studentId)

    suspend fun submitResultSlip(
        studentId: String,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double
    ): ResultSlip =
        ParentPortalDataSource.submitResultSlip(studentId, examName, examDate, subject, score, maxScore)

    suspend fun submitStaffResultSlip(
        studentId: String,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double,
        uploadedBy: String
    ): ResultSlip =
        ParentPortalDataSource.submitStaffResultSlip(studentId, examName, examDate, subject, score, maxScore, uploadedBy)

    suspend fun fetchMessages(studentId: String): List<ParentMessage> =
        ParentPortalDataSource.fetchMessages(studentId)

    suspend fun sendParentMessage(
        studentId: String,
        subject: String?,
        body: String
    ): ParentMessage =
        ParentPortalDataSource.sendParentMessage(studentId, subject, body)

    suspend fun fetchFeatureFlags(): Map<String, Boolean> =
        MediaExportDataSource.fetchFeatureFlags()

    suspend fun uploadStudentPhoto(studentId: String, fileName: String, bytes: ByteArray): String =
        MediaExportDataSource.uploadStudentPhoto(studentId, fileName, bytes)

    suspend fun signedStudentPhotoUrl(path: String): String =
        MediaExportDataSource.signedStudentPhotoUrl(path)

    suspend fun registerDeviceToken(token: String, platform: String = "android") =
        MediaExportDataSource.registerDeviceToken(token, platform)

    suspend fun fetchTodayDismissals(): List<Dismissal> =
        KioskAttendanceDataSource.fetchTodayDismissals()

    fun awaitingSafelyHome(dismissals: List<Dismissal>): List<Dismissal> =
        KioskAttendanceDataSource.awaitingSafelyHome(dismissals)

    suspend fun markSafelyHome(dismissalId: String) =
        KioskAttendanceDataSource.markSafelyHome(dismissalId)

    suspend fun syncPending(records: List<PendingAttendanceRecord>): SyncResult {
        val (synced, skipped, blocked) = SessionAttendanceDataSource.syncPending(records)
        return SyncResult(synced, skipped, blocked)
    }

}

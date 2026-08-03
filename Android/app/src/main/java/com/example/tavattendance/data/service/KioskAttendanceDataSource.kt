package com.example.tavattendance.data.service

import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.*
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.*

internal object KioskAttendanceDataSource {
    private val db get() = SupabaseClient.client

    suspend fun fetchKioskEntries(): List<KioskEntry> {
        // Day-aware: only create/show sessions for classes scheduled today, so opening the
        // kiosk on a non-tuition day doesn't spin up phantom sessions. Supports multiple
        // classes on the same day (e.g. Thu English + Thu Reading).
        val todayWeekday = weekdayName(Date())
        val testMode = FeatureFlags.isEnabled(FeatureFlags.TEST_MODE)
        val classes = ClassStudentDataSource.fetchMyClasses().filter {
            shouldShowKioskClass(
                canOperateTodaySession = it.canOperateTodaySession,
                meetsToday = classMeetsToday(it, todayWeekday),
                testMode = testMode,
            )
        }
        val classMap = classes.associateBy { it.id }

        val sessionTuples = classes.map { cls ->
            cls.id to SessionAttendanceDataSource.getOrCreateTodaySession(classId = cls.id)
        }

        // PERF-02: fetch rosters in parallel instead of sequentially.
        // Each async block runs concurrently; awaitAll collects in declaration order,
        // preserving the (classId, session) association via the paired result.
        val rosterResults: List<Pair<Pair<String, Session>, List<RosterEntry>>> =
            coroutineScope {
                sessionTuples
                    .map { pair -> async { pair to SessionAttendanceDataSource.fetchRoster(pair.second.id) } }
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

    // late > present > absent
    fun worstStatus(a: AttendanceStatus?, b: AttendanceStatus?): AttendanceStatus? {
        val rank = mapOf(
            AttendanceStatus.late to 4,
            AttendanceStatus.present to 3,
            AttendanceStatus.absent to 2,
        )
        return when {
            a == null -> b
            b == null -> a
            (rank[b] ?: 0) > (rank[a] ?: 0) -> b
            else -> a
        }
    }

    fun shouldShowKioskClass(
        canOperateTodaySession: Boolean,
        meetsToday: Boolean,
        testMode: Boolean,
    ): Boolean = canOperateTodaySession && (testMode || meetsToday)

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
        val session = SessionAttendanceDataSource.getOrCreateTodaySession(classId = STUDY_SPACE_CLASS_ID)
        val roster = db.postgrest
            .rpc("get_study_space_roster", buildJsonObject { put("p_session_id", session.id) })
            .decodeList<RosterEntry>()
        return session to roster
    }

    suspend fun markKioskAttendance(entry: KioskEntry, status: AttendanceStatus) {
        for (session in entry.sessions) {
            SessionAttendanceDataSource.markAttendance(
                sessionId = session.id,
                studentId = entry.studentId,
                status = status,
            )
        }
    }

    suspend fun clearKioskAttendance(entry: KioskEntry) {
        for (session in entry.sessions) {
            SessionAttendanceDataSource.clearAttendance(session.id, entry.studentId)
        }
    }

    suspend fun markKioskSignIn(entry: KioskEntry): AttendanceStatus {
        val now = Date()
        var worst = AttendanceStatus.present
        for (session in entry.sessions) {
            val status = signInStatus(session, now)
            SessionAttendanceDataSource.markAttendance(
                sessionId = session.id,
                studentId = entry.studentId,
                status = status,
            )
            if (status == AttendanceStatus.late) worst = status
        }
        return worst
    }

    /** Present, or late when the session has started (or its scheduled time has passed). */
    fun signInStatus(session: KioskSession, now: Date): AttendanceStatus {
        val startedAt = session.startedAt?.let {
            runCatching { java.time.Instant.parse(it).let { i -> Date(i.toEpochMilli()) } }.getOrNull()
        }
        if (startedAt != null && now.after(startedAt)) return AttendanceStatus.late
        if (session.scheduleTime != null) {
            // Split on ":" taking first two parts — handles both "HH:mm" and "HH:mm:ss"
            val parts = session.scheduleTime.split(":").mapNotNull { it.toIntOrNull() }
            if (parts.size >= 2) {
                val classCal = Calendar.getInstance().apply { time = now }
                classCal.set(Calendar.HOUR_OF_DAY, parts[0])
                classCal.set(Calendar.MINUTE, parts[1])
                classCal.set(Calendar.SECOND, 0)
                classCal.set(Calendar.MILLISECOND, 0)
                if (now.after(classCal.time)) return AttendanceStatus.late
            }
        }
        return AttendanceStatus.present
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

}

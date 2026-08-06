package com.example.tavattendance.data.service

import com.example.tavattendance.data.models.AttendanceHistoryRecord
import com.example.tavattendance.data.models.AttendanceStatus
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.roundToInt

data class ClassYearSummary(
    val className: String,
    val totalSessions: Int,
    val presentCount: Int,
    val lateCount: Int,
    val absentCount: Int,
) {
    /**
     * null when totalSessions == 0. Matches the `attendance_summary` formula:
     * (present + late) / total, rounded to 1 decimal place.
     */
    val attendancePct: Double?
        get() {
            if (totalSessions == 0) return null
            val raw = 100.0 * (presentCount + lateCount).toDouble() / totalSessions.toDouble()
            return (raw * 10).roundToInt() / 10.0
        }
}

/** Pure rolling 12-month aggregation for the Students-tab year-detail screen. */
object StudentYearSummary {
    private val singapore = ZoneId.of("Asia/Singapore")

    /** Rolling 12 months back from [now]. */
    fun windowStart(from: LocalDate = LocalDate.now(singapore)): LocalDate =
        from.minusYears(1)

    /** ISO date string for PostgREST `since` filter. */
    fun windowStartIso(from: LocalDate = LocalDate.now(singapore)): String =
        windowStart(from).toString()

    /**
     * Groups history by class name, sorted by class name ascending (matches web's
     * `.order('class_name')`).
     */
    fun byClass(records: List<AttendanceHistoryRecord>): List<ClassYearSummary> {
        data class Bucket(var present: Int = 0, var late: Int = 0, var absent: Int = 0, var total: Int = 0)
        val buckets = linkedMapOf<String, Bucket>()
        for (record in records) {
            val name = record.session.cls.name
            val bucket = buckets.getOrPut(name) { Bucket() }
            bucket.total += 1
            when (record.status) {
                AttendanceStatus.present -> bucket.present += 1
                AttendanceStatus.late -> bucket.late += 1
                AttendanceStatus.absent -> bucket.absent += 1
            }
        }
        return buckets.keys.sorted().map { name ->
            val b = buckets.getValue(name)
            ClassYearSummary(
                className = name,
                totalSessions = b.total,
                presentCount = b.present,
                lateCount = b.late,
                absentCount = b.absent,
            )
        }
    }
}

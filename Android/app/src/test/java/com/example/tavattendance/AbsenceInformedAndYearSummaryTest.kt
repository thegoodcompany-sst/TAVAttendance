package com.example.tavattendance

import com.example.tavattendance.data.models.AttendanceHistoryRecord
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.service.StudentYearSummary
import com.example.tavattendance.data.service.SyncAttendancePayload
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class AbsenceInformedAndYearSummaryTest {

    private val json = Json { encodeDefaults = false }

    @Test
    fun syncAttendancePayloadEncodesAbsenceInformedTrueAndOmitsWhenNull() {
        val withFlag = SyncAttendancePayload(
            sessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            studentId = "11111111-2222-3333-4444-555555555555",
            status = "absent",
            notes = "",
            clientMutationId = "m1",
            markedAt = "2026-08-06T00:00:00Z",
            absenceInformed = true
        )
        val encoded = json.encodeToString(SyncAttendancePayload.serializer(), withFlag)
        val obj = json.parseToJsonElement(encoded) as JsonObject
        assertEquals(true, obj["absence_informed"]?.jsonPrimitive?.boolean)

        val withoutFlag = withFlag.copy(clientMutationId = "m2", absenceInformed = null)
        val encoded2 = json.encodeToString(SyncAttendancePayload.serializer(), withoutFlag)
        val obj2 = json.parseToJsonElement(encoded2) as JsonObject
        assertFalse(obj2.containsKey("absence_informed"))
        assertNull(obj2["absence_informed"])
    }

    @Test
    fun studentYearSummaryWindowStartIsOneYearEarlier() {
        val now = LocalDate.of(2026, 8, 6)
        assertEquals(LocalDate.of(2025, 8, 6), StudentYearSummary.windowStart(now))
        assertEquals("2025-08-06", StudentYearSummary.windowStartIso(now))
    }

    @Test
    fun studentYearSummaryByClassAggregatesAndSorts() {
        val records = listOf(
            historyRecord("Math (Mon)", AttendanceStatus.present),
            historyRecord("English (Thu)", AttendanceStatus.late),
            historyRecord("Math (Mon)", AttendanceStatus.absent),
            historyRecord("Math (Mon)", AttendanceStatus.present),
            historyRecord("English (Thu)", AttendanceStatus.present),
        )
        val summaries = StudentYearSummary.byClass(records)
        assertEquals(listOf("English (Thu)", "Math (Mon)"), summaries.map { it.className })
        assertEquals(2, summaries[0].totalSessions)
        assertEquals(1, summaries[0].presentCount)
        assertEquals(1, summaries[0].lateCount)
        assertEquals(0, summaries[0].absentCount)
        assertEquals(100.0, summaries[0].attendancePct)
        assertEquals(3, summaries[1].totalSessions)
        assertEquals(2, summaries[1].presentCount)
        assertEquals(0, summaries[1].lateCount)
        assertEquals(1, summaries[1].absentCount)
        assertEquals(66.7, summaries[1].attendancePct)
    }

    @Test
    fun studentYearSummaryEmptyInput() {
        assertTrue(StudentYearSummary.byClass(emptyList()).isEmpty())
    }

    private fun historyRecord(
        className: String,
        status: AttendanceStatus
    ): AttendanceHistoryRecord = AttendanceHistoryRecord(
        id = java.util.UUID.randomUUID().toString(),
        status = status,
        markedAt = null,
        absenceInformed = null,
        session = AttendanceHistoryRecord.SessionSummary(
            sessionDate = "2026-07-01",
            cls = AttendanceHistoryRecord.SessionSummary.ClassSummary(name = className)
        )
    )
}

package com.example.tavattendance

import com.example.tavattendance.data.service.StudentAttendanceHistoryQuery
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Contract: staff student history must exclude Study Space via the same constants
 * [SessionAttendanceDataSource.fetchStudentAttendanceHistory] uses.
 */
class StudentAttendanceHistoryQueryTest {

    @Test
    fun excludesStudySpace_viaShippedSelectAndFilterConstants() {
        assertTrue(StudentAttendanceHistoryQuery.excludesStudySpace())
        assertEquals(
            "session.class.is_study_space",
            StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_COLUMN
        )
        assertFalse(StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_VALUE)
        // SELECT must stay compatible with ClassSummary(name-only) decode.
        assertFalse(
            StudentAttendanceHistoryQuery.SELECT.contains("is_study_space")
        )
        assertTrue(
            StudentAttendanceHistoryQuery.SELECT.contains("class:classes!inner(name)")
        )
    }

    @Test
    fun historyRecordJson_withSelectShape_decodesWithoutUnknownKeys() {
        // Mirrors the SELECT payload: class has only `name` (no is_study_space).
        val json = """
            {
              "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
              "status": "present",
              "marked_at": "2026-08-05T10:00:00Z",
              "session": {
                "session_date": "2026-08-05",
                "class": { "name": "P5 Math" }
              }
            }
        """.trimIndent()
        val record = kotlinx.serialization.json.Json.Default
            .decodeFromString(
                com.example.tavattendance.data.models.AttendanceHistoryRecord.serializer(),
                json
            )
        assertEquals("P5 Math", record.session.cls.name)
        assertEquals(
            com.example.tavattendance.data.models.AttendanceStatus.present,
            record.status
        )
    }

    @Test
    fun historyRecordJson_withIsStudySpaceField_failsClosedOnDefaultJson() {
        // Documents why SELECT must not request is_study_space: Json.Default
        // rejects unknown keys, matching SupabaseClient configuration.
        val json = """
            {
              "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
              "status": "present",
              "marked_at": "2026-08-05T10:00:00Z",
              "session": {
                "session_date": "2026-08-05",
                "class": { "name": "P5 Math", "is_study_space": false }
              }
            }
        """.trimIndent()
        try {
            kotlinx.serialization.json.Json.Default.decodeFromString(
                com.example.tavattendance.data.models.AttendanceHistoryRecord.serializer(),
                json
            )
            org.junit.Assert.fail("expected decode to fail on unknown is_study_space key")
        } catch (_: kotlinx.serialization.SerializationException) {
            // expected
        }
    }
}

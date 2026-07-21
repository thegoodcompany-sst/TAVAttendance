package com.example.tavattendance

import com.example.tavattendance.data.models.RetrospectiveSessionRules
import com.example.tavattendance.data.models.Session
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class RetrospectiveSessionRulesTest {
    private val today = LocalDate.of(2026, 7, 10)

    private fun session(date: String) = Session(
        id = date,
        classId = "class-id",
        sessionDate = date,
        endedAt = "2026-07-10T00:00:00Z"
    )

    @Test
    fun retrospectiveDateMustBeBeforeToday() {
        assertTrue(RetrospectiveSessionRules.isPastDate("2026-07-09", today))
        assertFalse(RetrospectiveSessionRules.isPastDate("2026-07-10", today))
        assertFalse(RetrospectiveSessionRules.isPastDate("2026-07-11", today))
        assertFalse(RetrospectiveSessionRules.isPastDate("not-a-date", today))
    }

    @Test
    fun existingSessionDetectionUsesClassDateList() {
        val expected = session("2026-07-10")
        val sessions = listOf(session("2026-07-09"), expected)
        assertEquals(expected, RetrospectiveSessionRules.existingSession("2026-07-10", sessions))
        assertNull(RetrospectiveSessionRules.existingSession("2026-07-08", sessions))
    }

    @Test
    fun historicalEditorRequiresFlagAndPastDate() {
        assertTrue(RetrospectiveSessionRules.editorEnabled(session("2026-07-09"), true, today))
        assertFalse(RetrospectiveSessionRules.editorEnabled(session("2026-07-10"), true, today))
        assertFalse(RetrospectiveSessionRules.editorEnabled(session("2026-07-09"), false, today))
    }
}

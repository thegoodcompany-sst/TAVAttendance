package com.example.tavattendance

import com.example.tavattendance.data.models.Dismissal
import com.example.tavattendance.data.service.AttendanceService
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the safely-home filter (migration 030, flag `push_notifications`):
 * only dismissals with a dismissal time and no confirmation yet show the
 * "Mark safely home" card. Pure function, runs on the host JVM.
 */
class SafelyHomeTest {

    private fun dismissal(id: String, dismissedAt: String?, safelyHomeAt: String?) =
        Dismissal(id = id, studentId = "s-$id", dismissedAt = dismissedAt, safelyHomeAt = safelyHomeAt)

    @Test
    fun unconfirmedDismissal_isAwaiting() {
        val d = dismissal("1", "2026-07-13T09:00:00+00:00", null)
        assertEquals(listOf(d), AttendanceService.awaitingSafelyHome(listOf(d)))
    }

    @Test
    fun confirmedDismissal_isExcluded() {
        val d = dismissal("1", "2026-07-13T09:00:00+00:00", "2026-07-13T09:30:00+00:00")
        assertTrue(AttendanceService.awaitingSafelyHome(listOf(d)).isEmpty())
    }

    @Test
    fun dismissalWithoutTimestamp_isExcluded() {
        val d = dismissal("1", null, null)
        assertTrue(AttendanceService.awaitingSafelyHome(listOf(d)).isEmpty())
    }

    @Test
    fun mixedList_keepsOnlyUnconfirmed() {
        val awaiting = dismissal("1", "2026-07-13T09:00:00+00:00", null)
        val confirmed = dismissal("2", "2026-07-13T09:00:00+00:00", "2026-07-13T10:00:00+00:00")
        assertEquals(listOf(awaiting), AttendanceService.awaitingSafelyHome(listOf(confirmed, awaiting)))
    }
}

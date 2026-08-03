package com.example.tavattendance

import com.example.tavattendance.data.models.TAVClass
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.KioskSession
import com.example.tavattendance.data.service.AttendanceService
import java.util.Calendar
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the day-aware kiosk filter (migration 015). `classMeetsToday` is a pure
 * function, so it runs on the host JVM without a Supabase client.
 */
class DayAwareKioskTest {

    private fun cls(
        scheduleDay: String? = null,
        recurrenceRule: String? = null
    ) = TAVClass(
        id = "c1",
        name = "Test",
        scheduleDay = scheduleDay,
        recurrenceRule = recurrenceRule
    )

    @Test
    fun scheduleDay_matchesOnlyItsDay() {
        val monday = cls(scheduleDay = "Monday")
        assertTrue(AttendanceService.classMeetsToday(monday, "Monday"))
        assertFalse(AttendanceService.classMeetsToday(monday, "Wednesday"))
    }

    @Test
    fun scheduleDay_isCaseInsensitive() {
        assertTrue(AttendanceService.classMeetsToday(cls(scheduleDay = "thursday"), "Thursday"))
    }

    @Test
    fun multipleClassesSameDay_bothMatch() {
        // TAVA runs English + Reading both on Thursday — both must show.
        assertTrue(AttendanceService.classMeetsToday(cls(scheduleDay = "Thursday"), "Thursday"))
        assertTrue(AttendanceService.classMeetsToday(cls(scheduleDay = "Thursday"), "Thursday"))
    }

    @Test
    fun recurrenceRule_bydayWinsOverScheduleDay() {
        val monThu = cls(scheduleDay = "Monday", recurrenceRule = "FREQ=WEEKLY;BYDAY=MO,TH")
        assertTrue(AttendanceService.classMeetsToday(monThu, "Monday"))
        assertTrue(AttendanceService.classMeetsToday(monThu, "Thursday"))
        assertFalse(AttendanceService.classMeetsToday(monThu, "Tuesday"))
    }

    @Test
    fun noDayAndNoRecurrence_alwaysShown() {
        val adhoc = cls()
        assertTrue(AttendanceService.classMeetsToday(adhoc, "Monday"))
        assertTrue(AttendanceService.classMeetsToday(adhoc, "Sunday"))
    }

    @Test
    fun testModeBypassesOnlyTheDayFilter() {
        assertTrue(AttendanceService.shouldShowKioskClass(true, false, true))
        assertFalse(AttendanceService.shouldShowKioskClass(false, true, true))
        assertFalse(AttendanceService.shouldShowKioskClass(true, false, false))
    }

    @Test
    fun worstStatusUsesThreeStoredValuesAndHandlesUnmarkedStudents() {
        assertEquals(AttendanceStatus.late, AttendanceService.worstStatus(AttendanceStatus.present, AttendanceStatus.late))
        assertEquals(AttendanceStatus.present, AttendanceService.worstStatus(AttendanceStatus.present, AttendanceStatus.absent))
        assertEquals(AttendanceStatus.absent, AttendanceService.worstStatus(null, AttendanceStatus.absent))
        assertNull(AttendanceService.worstStatus(null, null))
    }

    @Test
    fun futureStartedAtStillFallsBackToPastSchedule() {
        val now = Calendar.getInstance().apply {
            set(2026, Calendar.JULY, 10, 20, 30, 0)
            set(Calendar.MILLISECOND, 0)
        }.time
        val future = java.time.Instant.ofEpochMilli(now.time + 30 * 60 * 1000).toString()

        assertEquals(
            AttendanceStatus.late,
            AttendanceService.signInStatus(KioskSession("s", "20:00:00", future), now),
        )
    }
}

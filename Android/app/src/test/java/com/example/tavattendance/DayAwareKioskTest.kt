package com.example.tavattendance

import com.example.tavattendance.data.models.TAVClass
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.KioskSession
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.KioskAttendanceDataSource
import java.time.Instant
import java.util.Calendar
import java.util.Date
import java.util.TimeZone
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

    private fun singaporeWallClock(year: Int, month: Int, day: Int, hour: Int, minute: Int): Date =
        Calendar.getInstance(TimeZone.getTimeZone("Asia/Singapore")).apply {
            set(year, month, day, hour, minute, 0)
            set(Calendar.MILLISECOND, 0)
        }.time

    @Test
    fun futureStartedAtStillFallsBackToPastSchedule() {
        val now = singaporeWallClock(2026, Calendar.JULY, 10, 20, 30)
        val future = Instant.ofEpochMilli(now.time + 30 * 60 * 1000).toString()

        assertEquals(
            AttendanceStatus.late,
            AttendanceService.signInStatus(KioskSession("s", "20:00:00", future), now),
        )
    }

    @Test
    fun malformedScheduleTimeFallsThroughToPresent() {
        val now = singaporeWallClock(2026, Calendar.JULY, 10, 20, 30)
        assertEquals(
            AttendanceStatus.present,
            AttendanceService.signInStatus(KioskSession("s", "garbage", null), now),
        )
        assertEquals(
            AttendanceStatus.present,
            AttendanceService.signInStatus(KioskSession("s", "20", null), now),
        )
    }

    @Test
    fun kioskClockUsesSingaporeWhenDeviceTimezoneIsUtc() {
        val previous = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        try {
            // Singapore Monday 01:30 = UTC Sunday 17:30.
            val mondayMorning = Date.from(Instant.parse("2026-08-23T17:30:00Z"))
            val weekday = AttendanceService.weekdayName(mondayMorning)
            assertEquals("Monday", weekday)
            assertEquals("2026-08-24", KioskAttendanceDataSource.singaporeDateIso(mondayMorning))
            assertTrue(AttendanceService.classMeetsToday(cls(scheduleDay = "Monday"), weekday))
            assertFalse(AttendanceService.classMeetsToday(cls(scheduleDay = "Sunday"), weekday))

            // Singapore Monday 08:30, class at 08:00 → late on SGT wall clock.
            val afterStart = Date.from(Instant.parse("2026-08-24T00:30:00Z"))
            assertEquals(
                AttendanceStatus.late,
                AttendanceService.signInStatus(KioskSession("s", "08:00:00", null), afterStart),
            )
            assertEquals(
                AttendanceStatus.present,
                AttendanceService.signInStatus(KioskSession("s", "garbage", null), afterStart),
            )

            val end = KioskAttendanceDataSource.scheduledEndTime(
                "19:00:00",
                120,
                Date.from(Instant.parse("2026-08-24T13:30:00Z")),
            )
            assertNotNull(end)
            assertTrue(Date.from(Instant.parse("2026-08-24T13:30:00Z")).after(end))
        } finally {
            TimeZone.setDefault(previous)
        }
    }
}

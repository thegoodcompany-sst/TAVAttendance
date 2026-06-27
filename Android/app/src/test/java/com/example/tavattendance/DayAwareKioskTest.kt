package com.example.tavattendance

import com.example.tavattendance.data.models.TAVClass
import com.example.tavattendance.data.service.AttendanceService
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
}

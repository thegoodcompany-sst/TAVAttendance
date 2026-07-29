package com.example.tavattendance

import com.example.tavattendance.data.models.ResultSlipInputValidation
import com.example.tavattendance.screens.ParentProfileTab
import com.example.tavattendance.screens.availableStudentProfileTabs
import com.example.tavattendance.screens.profileStateKey
import com.example.tavattendance.screens.retryableLoadError
import com.example.tavattendance.screens.shouldResetStudentProfileState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StudentProfileStateTest {
    @Test
    fun parentSeesAttendanceResultsAndMessagesTabs() {
        assertEquals(
            listOf(
                ParentProfileTab.Attendance,
                ParentProfileTab.Results,
                ParentProfileTab.Messages,
            ),
            availableStudentProfileTabs(parentMode = true),
        )
    }

    @Test
    fun staffSeesAttendanceTabOnly() {
        assertEquals(
            listOf(ParentProfileTab.Attendance),
            availableStudentProfileTabs(parentMode = false),
        )
    }

    @Test
    fun studentChangeResetsStudentSpecificStateKey() {
        val previous = profileStateKey("student-a", parentMode = false, canManageStaffResults = true)
        val next = profileStateKey("student-b", parentMode = false, canManageStaffResults = true)
        assertTrue(shouldResetStudentProfileState(previous, next))
        assertFalse(shouldResetStudentProfileState(next, next))
        assertFalse(shouldResetStudentProfileState(null, next))
    }

    @Test
    fun failedLoadsRetainRetryableErrorState() {
        assertTrue(retryableLoadError("Could not load history"))
        assertFalse(retryableLoadError(null))
        assertFalse(retryableLoadError(""))
    }

    @Test
    fun resultScoreValidationRejectsInvalidRanges() {
        assertNull(ResultSlipInputValidation.validate("CA1", 25.0, 35.0))
        assertTrue(ResultSlipInputValidation.validate("CA1", -1.0, 35.0) != null)
        assertTrue(ResultSlipInputValidation.validate("CA1", 40.0, 35.0) != null)
        assertTrue(ResultSlipInputValidation.validate("CA1", 10.0, 0.0) != null)
    }
}

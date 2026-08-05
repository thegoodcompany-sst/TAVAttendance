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
        assertTrue(
            StudentAttendanceHistoryQuery.SELECT.contains("is_study_space")
        )
        assertEquals(
            "session.class.is_study_space",
            StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_COLUMN
        )
        assertFalse(StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_VALUE)
    }
}

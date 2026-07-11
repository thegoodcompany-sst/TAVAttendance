package com.example.tavattendance

import com.example.tavattendance.data.models.ResultSubject
import com.example.tavattendance.data.models.classifyPrimaryLevel
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for the pure helpers behind tutor grade entry / class subject dropdown
 * (migration 023). Mirrors the iOS AttendanceLogicTests additions.
 */
class StudentResultsTest {

    @Test
    fun subjectNormalization() {
        assertEquals(ResultSubject.MATH, ResultSubject.normalizing("Math"))
        assertEquals(ResultSubject.MATH, ResultSubject.normalizing("Mathematics "))
        assertEquals(ResultSubject.ENGLISH, ResultSubject.normalizing("english"))
        assertEquals(ResultSubject.ENGLISH, ResultSubject.normalizing("English "))
        assertNull(ResultSubject.normalizing("Science"))
        assertNull(ResultSubject.normalizing(null))
        assertNull(ResultSubject.normalizing(""))
    }

    @Test
    fun primaryLevelInference() {
        assertEquals(true, classifyPrimaryLevel("P5"))
        assertEquals(true, classifyPrimaryLevel("Primary 4"))
        assertEquals(false, classifyPrimaryLevel("Sec 2"))
        assertEquals(false, classifyPrimaryLevel("sec 2 but he doesn't study"))
        assertNull(classifyPrimaryLevel("3"))
        assertNull(classifyPrimaryLevel(null))
    }
}

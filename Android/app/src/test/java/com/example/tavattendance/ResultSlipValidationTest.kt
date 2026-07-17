package com.example.tavattendance

import com.example.tavattendance.data.models.ResultSlipInputValidation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Mirrors iOS ResultSlipInputValidation tests for native parent portal Phase 2.
 */
class ResultSlipValidationTest {

    @Test
    fun acceptsValid() {
        assertNull(ResultSlipInputValidation.validate("CA1", 25.0, 35.0))
        assertNull(ResultSlipInputValidation.validate("  Mid-year  ", 0.0, 100.0))
    }

    @Test
    fun rejectsEmptyExamName() {
        assertEquals(
            ResultSlipInputValidation.Failure.EMPTY_EXAM_NAME,
            ResultSlipInputValidation.validate("  ", 10.0, 20.0)
        )
        assertEquals(
            ResultSlipInputValidation.Failure.EMPTY_EXAM_NAME,
            ResultSlipInputValidation.validate("", 10.0, 20.0)
        )
    }

    @Test
    fun rejectsInvalidScores() {
        assertEquals(
            ResultSlipInputValidation.Failure.INVALID_SCORE,
            ResultSlipInputValidation.validate("CA1", -1.0, 20.0)
        )
        assertEquals(
            ResultSlipInputValidation.Failure.INVALID_SCORE,
            ResultSlipInputValidation.validate("CA1", null, 20.0)
        )
        assertEquals(
            ResultSlipInputValidation.Failure.INVALID_SCORE,
            ResultSlipInputValidation.validate("CA1", Double.NaN, 20.0)
        )
        assertEquals(
            ResultSlipInputValidation.Failure.INVALID_MAX_SCORE,
            ResultSlipInputValidation.validate("CA1", 10.0, 0.0)
        )
        assertEquals(
            ResultSlipInputValidation.Failure.INVALID_MAX_SCORE,
            ResultSlipInputValidation.validate("CA1", 10.0, -5.0)
        )
        assertEquals(
            ResultSlipInputValidation.Failure.SCORE_EXCEEDS_MAX,
            ResultSlipInputValidation.validate("CA1", 21.0, 20.0)
        )
    }
}

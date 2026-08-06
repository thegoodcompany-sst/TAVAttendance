package com.example.tavattendance.data.service

/**
 * PostgREST shape for staff student attendance history.
 * Study Space rows must never appear in this projection (CLAUDE.md invariant).
 *
 * SELECT stays name-only so [AttendanceHistoryRecord.ClassSummary] can decode with
 * the client's default Json (ignoreUnknownKeys=false). Exclusion is the filter.
 */
object StudentAttendanceHistoryQuery {
    /**
     * Columns decoded into [AttendanceHistoryRecord]. Do not add `is_study_space`
     * here unless ClassSummary gains a matching optional field.
     */
    const val SELECT =
        "id, status, marked_at, absence_informed, session:sessions!inner(session_date, class:classes!inner(name))"

    /** PostgREST filter path used to drop study-space classes. */
    const val STUDY_SPACE_FILTER_COLUMN = "session.class.is_study_space"

    /** Filter value: only non-study-space classes. */
    const val STUDY_SPACE_FILTER_VALUE = false

    /** Contract helper for unit tests and any future call sites. */
    fun excludesStudySpace(): Boolean =
        STUDY_SPACE_FILTER_COLUMN == "session.class.is_study_space" &&
            !STUDY_SPACE_FILTER_VALUE &&
            // DECODE safety: payload must not request fields ClassSummary cannot hold.
            !SELECT.contains("is_study_space")
}

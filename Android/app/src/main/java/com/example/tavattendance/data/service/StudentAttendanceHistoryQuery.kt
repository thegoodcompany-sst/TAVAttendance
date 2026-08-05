package com.example.tavattendance.data.service

/**
 * PostgREST shape for staff student attendance history.
 * Study Space rows must never appear in this projection (CLAUDE.md invariant).
 */
object StudentAttendanceHistoryQuery {
    /** Embed includes `is_study_space` so the filter can target the class row. */
    const val SELECT =
        "id, status, marked_at, session:sessions!inner(session_date, class:classes!inner(name, is_study_space))"

    /** PostgREST filter path used to drop study-space classes. */
    const val STUDY_SPACE_FILTER_COLUMN = "session.class.is_study_space"

    /** Filter value: only non-study-space classes. */
    const val STUDY_SPACE_FILTER_VALUE = false

    /** Contract helper for unit tests and any future call sites. */
    fun excludesStudySpace(): Boolean =
        SELECT.contains("is_study_space") &&
            STUDY_SPACE_FILTER_COLUMN == "session.class.is_study_space" &&
            !STUDY_SPACE_FILTER_VALUE
}

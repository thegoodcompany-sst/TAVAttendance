import Foundation

/// PostgREST shape for staff student attendance history.
/// Study Space rows must never appear in this projection (CLAUDE.md invariant).
enum StudentAttendanceHistoryQuery {
    /// Embed includes `is_study_space` so the filter can target the class row.
    static let select =
        "id, status, marked_at, session:sessions!inner(session_date, class:classes!inner(name, is_study_space))"

    /// PostgREST filter path used to drop study-space classes.
    static let studySpaceFilterColumn = "session.class.is_study_space"

    /// Filter value: only non-study-space classes.
    static let studySpaceFilterValue = false

    /// Contract helper for unit tests and any future call sites.
    static var excludesStudySpace: Bool {
        select.contains("is_study_space")
            && studySpaceFilterColumn == "session.class.is_study_space"
            && studySpaceFilterValue == false
    }
}

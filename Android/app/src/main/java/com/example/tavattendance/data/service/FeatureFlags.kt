package com.example.tavattendance.data.service

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Feature flags backed by the `feature_flags` Postgres table (migration 012).
 * Flags ship OFF; an admin flips them when a feature is ready. Mirrors the iOS
 * FeatureFlagStore. Call [load] after sign-in; read with [isEnabled].
 */
object FeatureFlags {
    const val PARENT_PORTAL = "parent_portal"
    const val PUSH_NOTIFICATIONS = "push_notifications"
    const val STUDENT_PHOTOS = "student_photos"
    const val STUDY_SPACE_TRACKING = "study_space_tracking"
    const val SESSION_NOTES = "session_notes"

    private val _flags = MutableStateFlow<Map<String, Boolean>>(emptyMap())
    val flags: StateFlow<Map<String, Boolean>> = _flags.asStateFlow()

    suspend fun load() {
        _flags.value = AttendanceService.fetchFeatureFlags()
    }

    fun isEnabled(key: String): Boolean = _flags.value[key] == true
}

package com.example.tavattendance.auth

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.tavattendance.core.Analytics
import com.example.tavattendance.core.SafeLog
import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.Profile
import com.example.tavattendance.data.service.FeatureFlags
import com.example.tavattendance.data.store.PendingAttendanceStore
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val supabase = SupabaseClient.client
    private val pendingAttendanceStore = PendingAttendanceStore(application)

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated = _isAuthenticated.asStateFlow()

    private val _currentProfile = MutableStateFlow<Profile?>(null)
    val currentProfile = _currentProfile.asStateFlow()

    private val _authError = MutableStateFlow<String?>(null)
    val authError = _authError.asStateFlow()

    // Profile fetch can fail (network) — a silent swallow here would leave currentProfile
    // null and route an admin into the tutor UI. Surface it so the caller can retry instead.
    private val _profileError = MutableStateFlow<String?>(null)
    val profileError = _profileError.asStateFlow()

    private var pendingUserId: String? = null

    init {
        viewModelScope.launch {
            supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        val userId = status.session.user?.id
                        if (userId != null) pendingAttendanceStore.activateOwner(userId)
                        else pendingAttendanceStore.clear()
                        _isAuthenticated.value = userId != null
                        pendingUserId = userId
                        if (userId != null) fetchProfile(userId)
                        viewModelScope.launch {
                            runCatching { FeatureFlags.load() }
                            // Analytics is a no-op until the `analytics` flag is ON; start it
                            // only after flags load so app_launch/crash events aren't dropped.
                            Analytics.userId = userId
                            Analytics.role = _currentProfile.value?.role
                            runCatching { Analytics.start(getApplication<Application>()) }
                            // No-op unless the push_notifications flag is ON.
                            com.example.tavattendance.push.PushTokenRegistrar.registerIfEnabled()
                        }
                        _isLoading.value = false
                    }
                    is SessionStatus.NotAuthenticated -> {
                        pendingAttendanceStore.clear()
                        _isAuthenticated.value = false
                        _currentProfile.value = null
                        _isLoading.value = false
                    }
                    is SessionStatus.Initializing -> {
                        _isLoading.value = true
                    }
                    is SessionStatus.RefreshFailure -> {
                        _isLoading.value = false
                    }
                }
            }
        }
    }

    private suspend fun fetchProfile(userId: String) {
        runCatching {
            val profile = supabase.from("profiles").select {
                filter { eq("id", userId) }
            }.decodeSingle<Profile>()
            _currentProfile.value = profile
            _profileError.value = null
        }.onFailure { e ->
            SafeLog.error("AuthVM", "fetchProfile failed", e)
            _profileError.value = e.localizedMessage ?: "Failed to load profile"
        }
    }

    fun retryFetchProfile() {
        val userId = pendingUserId ?: return
        viewModelScope.launch { fetchProfile(userId) }
    }

    fun signIn(email: String, password: String) {
        viewModelScope.launch {
            _authError.value = null
            runCatching {
                supabase.auth.signInWith(Email) {
                    this.email = email
                    this.password = password
                }
            }.onFailure { e ->
                val raw = e.message?.lines()?.firstOrNull()?.trim() ?: ""
                _authError.value = when {
                    raw.contains("invalid_credentials", ignoreCase = true) ||
                    raw.contains("Invalid login", ignoreCase = true) -> "Invalid email or password"
                    raw.contains("network", ignoreCase = true) ||
                    raw.contains("connect", ignoreCase = true) -> "Network error. Check your connection."
                    raw.isNotBlank() -> raw
                    else -> "Sign in failed"
                }
            }
        }
    }

    fun signOut() {
        // Clear synchronously before the auth request so no stale queue survives an
        // offline/failed sign-out or becomes visible to a subsequent account.
        pendingAttendanceStore.clear()
        viewModelScope.launch {
            runCatching { supabase.auth.signOut() }
        }
    }
}

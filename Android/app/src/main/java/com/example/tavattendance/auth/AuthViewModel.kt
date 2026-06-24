package com.example.tavattendance.auth

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.Profile
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val supabase = SupabaseClient.client

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated = _isAuthenticated.asStateFlow()

    private val _currentProfile = MutableStateFlow<Profile?>(null)
    val currentProfile = _currentProfile.asStateFlow()

    private val _authError = MutableStateFlow<String?>(null)
    val authError = _authError.asStateFlow()

    init {
        viewModelScope.launch {
            supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        _isAuthenticated.value = true
                        val userId = status.session.user?.id
                        if (userId != null) fetchProfile(userId)
                        _isLoading.value = false
                    }
                    is SessionStatus.NotAuthenticated -> {
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
        }
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
        viewModelScope.launch {
            runCatching { supabase.auth.signOut() }
        }
    }
}

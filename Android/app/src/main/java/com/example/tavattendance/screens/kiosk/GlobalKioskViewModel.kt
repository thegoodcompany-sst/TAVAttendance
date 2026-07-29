package com.example.tavattendance.screens.kiosk

import android.app.Application
import android.content.Context
import android.provider.Settings.Secure
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.tavattendance.core.Analytics
import com.example.tavattendance.core.AnalyticsEventType
import com.example.tavattendance.core.SafeLog
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.KioskEntry
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.Date

class GlobalKioskViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("kiosk_settings", Context.MODE_PRIVATE)

    private val _entries = MutableStateFlow<List<KioskEntry>>(emptyList())
    val entries = _entries.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _pendingIds = MutableStateFlow<Set<String>>(emptySet())
    val pendingIds = _pendingIds.asStateFlow()

    // SEC-02: persist lockout state in SharedPreferences so rotation / back
    // cannot reset the brute-force counter.
    private val _failedAttempts = MutableStateFlow(prefs.getInt("failed_attempts", 0))
    private val _lockedUntil = MutableStateFlow(prefs.getLong("locked_until", 0L))
    val lockedUntil = _lockedUntil.asStateFlow()

    // Persisted kiosk settings
    val storedPin: String get() = prefs.getString("pin", "") ?: ""

    // A configured PIN always starts locked. The persisted `locked=false` value only means an
    // admin unlocked the previous process; carrying that authorization across a cold start
    // would expose settings without a fresh PIN challenge.
    private val _isLocked = MutableStateFlow(shouldLockKioskOnStart(storedPin))
    val isLocked = _isLocked.asStateFlow()

    private val _isAdminUnlocked = MutableStateFlow(!_isLocked.value && storedPin.isEmpty())
    val isAdminUnlocked = _isAdminUnlocked.asStateFlow()

    private val _showPinUnlock = MutableStateFlow(false)
    val showPinUnlock = _showPinUnlock.asStateFlow()

    private val _showSettings = MutableStateFlow(false)
    val showSettings = _showSettings.asStateFlow()

    // SP-06: expose errors via StateFlow so the UI can display a Snackbar.
    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    // Distinguishes "load failed" from "genuinely no classes today" so the empty state
    // doesn't lie about there being nothing scheduled.
    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    // MAINT-10: derived StateFlow for isAdminMode — Compose will recompose
    // whenever isLocked or isAdminUnlocked changes.
    val isAdminMode = combine(_isAdminUnlocked, _isLocked) { adminUnlocked, locked ->
        !locked && (storedPin.isEmpty() || adminUnlocked)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, !_isLocked.value && (storedPin.isEmpty() || _isAdminUnlocked.value))

    init {
        prefs.edit().putBoolean("locked", _isLocked.value).apply()
        loadEntries()
    }

    fun loadEntries() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            val startMs = System.currentTimeMillis()
            runCatching { AttendanceService.fetchKioskEntries() }
                .onSuccess {
                    _entries.value = it
                    Analytics.track(AnalyticsEventType.OPS, "kiosk_load", buildJsonObject {
                        put("entry_count", it.size)
                        put("duration_ms", System.currentTimeMillis() - startMs)
                    })
                }
                .onFailure { e ->
                    SafeLog.error("GlobalKioskVM", "load kiosk entries failed", e)
                    // This screen is student-facing. Backend exception text can expose table,
                    // policy, or identifier details and therefore stays in debug-only logging.
                    val msg = "Could not load the sign-in list. Please ask a staff member to retry."
                    _snackbarMessage.value = msg
                    _loadError.value = msg
                }
            _isLoading.value = false
        }
    }

    fun clearSnackbar() { _snackbarMessage.value = null }

    fun onCardTap(entry: KioskEntry) {
        when {
            entry.status == null || entry.status == AttendanceStatus.excused ->
                handleAction(entry, KioskAction.SignIn)
            isAdminMode.value && entry.status != AttendanceStatus.present ->
                handleAction(entry, KioskAction.MarkPresent)
        }
    }

    fun handleAction(entry: KioskEntry, action: KioskAction) {
        // UI visibility is not an authorization boundary. Keep this guard at the mutation
        // entry point so stale Compose state or a future caller cannot run admin overrides
        // while the kiosk is locked.
        if (!isKioskActionAuthorized(action, hasAdminAuthorization())) return
        if (entry.studentId in _pendingIds.value) return
        _pendingIds.value = _pendingIds.value + entry.studentId

        // SP-06: apply optimistic UI update before the suspend call, then
        // surface any error via snackbarMessage on failure.
        viewModelScope.launch {
            runCatching {
                when (action) {
                    KioskAction.SignIn -> performSignIn(entry)
                    KioskAction.MarkPresent -> {
                        AttendanceService.markKioskAttendance(entry, AttendanceStatus.present)
                        updateEntry(entry.studentId, AttendanceStatus.present)
                    }
                    KioskAction.MarkLate -> {
                        AttendanceService.markKioskAttendance(entry, AttendanceStatus.late)
                        updateEntry(entry.studentId, AttendanceStatus.late)
                    }
                    KioskAction.MarkAbsent -> {
                        AttendanceService.markKioskAttendance(entry, AttendanceStatus.absent)
                        updateEntry(entry.studentId, AttendanceStatus.absent)
                    }
                    KioskAction.MarkNotHere -> {
                        AttendanceService.markKioskAttendance(entry, AttendanceStatus.excused)
                        updateEntry(entry.studentId, AttendanceStatus.excused)
                    }
                }
            }.onFailure { e ->
                SafeLog.error("GlobalKioskVM", "kiosk action failed", e)
                _snackbarMessage.value = "Sign-in failed. Please ask a staff member for help."
            }
            _pendingIds.value = _pendingIds.value - entry.studentId
        }
    }

    private suspend fun performSignIn(entry: KioskEntry) {
        AttendanceService.markKioskSignIn(entry)
        updateEntry(entry.studentId, computeSignInStatus(entry))
    }

    /**
     * QR sign-in (flag `qr_sign_in`): resolves the payload to a kiosk entry and runs
     * the exact same sign-in path as tapping the card. Returns the feedback line
     * shown in the scanner. Mirrors iOS handleScannedPayload.
     */
    suspend fun handleScannedPayload(payload: String): String {
        val id = AttendanceService.studentIdFromQrPayload(payload)
            ?: return "Not a student QR code"
        val entry = _entries.value.firstOrNull { it.studentId.lowercase() == id }
            ?: return "Student not found for today's classes"
        return when (entry.status) {
            null, AttendanceStatus.excused -> {
                val result = runCatching { performSignIn(entry) }
                val updated = _entries.value.firstOrNull { it.studentId == entry.studentId }
                val status = updated?.status
                if (result.isSuccess && status != null && status != AttendanceStatus.excused) {
                    "${entry.fullName} — ${if (status == AttendanceStatus.late) "Late" else "On Time"}"
                } else {
                    "Sign-in failed — please try again"
                }
            }
            AttendanceStatus.absent -> "${entry.fullName} — marked Absent, ask a teacher"
            else -> "${entry.fullName} — already signed in"
        }
    }

    private fun updateEntry(studentId: String, status: AttendanceStatus) {
        _entries.value = _entries.value.map { e ->
            if (e.studentId == studentId) e.copy(status = status, markedAt = java.time.Instant.now().toString())
            else e
        }
    }

    /** Late if any of the student's sessions has passed its start/scheduled time. */
    private fun computeSignInStatus(entry: KioskEntry): AttendanceStatus {
        val now = Date()
        return if (entry.sessions.any { AttendanceService.signInStatus(it, now) == AttendanceStatus.late })
            AttendanceStatus.late else AttendanceStatus.present
    }

    // -----------------------------------------------------------------------
    // PIN management  (SEC-01 + SEC-02)
    // -----------------------------------------------------------------------

    private val deviceSalt: String
        get() = Secure.getString(getApplication<Application>().contentResolver, Secure.ANDROID_ID)
            ?: "tava-kiosk-fallback"

    /** Set the PIN. Always stores a v2: PBKDF2 hash going forward. */
    fun setPin(pin: String) {
        if (!hasAdminAuthorization()) return
        prefs.edit().putString("pin", hashPinPbkdf2(pin, deviceSalt)).apply()
    }

    fun clearPin() {
        if (!hasAdminAuthorization()) return
        prefs.edit().remove("pin").putBoolean("locked", false).apply()
        _isLocked.value = false
        _isAdminUnlocked.value = true
        // Clear any lockout state when the PIN is removed.
        persistLockoutState(KioskLockoutState())
    }

    /** MAINT-10: update both SharedPreferences and the backing StateFlow. */
    fun lockKiosk() {
        if (storedPin.isEmpty()) return
        prefs.edit().putBoolean("locked", true).apply()
        _isLocked.value = true
        _isAdminUnlocked.value = false
        _showSettings.value = false
        Analytics.track(AnalyticsEventType.OPS, "admin_lock")
    }

    /** Revokes process-local admin authorization whenever the app leaves the foreground. */
    fun relockConfiguredKiosk() {
        if (storedPin.isEmpty()) return
        // Revoke authorization before publishing the lock-state transition.
        _isAdminUnlocked.value = false
        _isLocked.value = true
        _showSettings.value = false
        _showPinUnlock.value = false
        prefs.edit().putBoolean("locked", true).apply()
    }

    /**
     * SEC-01: verify the entered PIN against the stored hash.
     *
     * Migration path:
     *  - No stored PIN → always false (nothing to verify against).
     *  - Stored value starts with "v2:" → compare against new PBKDF2 hash.
     *  - Stored value starts with "v1:" (legacy single-round SHA-256) →
     *      verify with old method; on success re-hash with PBKDF2 and re-store.
     *  - Stored value has no recognised prefix (pre-hashing plaintext) →
     *      treat as legacy plaintext comparison; on success re-hash and re-store.
     *
     * SEC-02: lockout checking, PIN verification, and failure recording happen
     *         under one lock. Callers cannot bypass throttling by invoking PIN
     *         verification directly or forgetting a separate failure callback.
     *
     * Returns a structured result so the UI renders the state produced by this
     * exact attempt rather than a stale Compose snapshot.
     */
    internal fun tryUnlock(pin: String): KioskUnlockResult = synchronized(kioskPinAttemptLock) {
        val nowMillis = System.currentTimeMillis()
        val currentState = KioskLockoutState(
            failedAttempts = prefs.getInt("failed_attempts", 0),
            lockoutStage = prefs.getInt("lockout_stage", 0),
            lockedUntilMillis = prefs.getLong("locked_until", 0L),
        )
        _failedAttempts.value = currentState.failedAttempts
        _lockedUntil.value = currentState.lockedUntilMillis
        if (isKioskUnlockBlocked(currentState, nowMillis)) {
            return@synchronized KioskUnlockResult.LockedOut(currentState.lockedUntilMillis)
        }

        val stored = storedPin
        if (stored.isEmpty()) return@synchronized KioskUnlockResult.NotConfigured

        val matches: Boolean = when {
            stored.startsWith("v2:") -> {
                // Current PBKDF2 scheme.
                secureEquals(hashPinPbkdf2(pin, deviceSalt), stored)
            }
            stored.startsWith("v1:") -> {
                // Legacy single-round SHA-256.
                secureEquals(hashPinLegacy(pin, deviceSalt), stored)
            }
            else -> {
                // Very old plaintext PIN (pre-hashing era) — compare directly.
                secureEquals(pin, stored)
            }
        }

        val (nextState, result) = transitionKioskUnlockState(currentState, matches, nowMillis)
        persistLockoutState(nextState)

        if (result == KioskUnlockResult.Unlocked) {
            // Re-hash with PBKDF2 if the stored value used an older scheme.
            if (!stored.startsWith("v2:")) {
                prefs.edit().putString("pin", hashPinPbkdf2(pin, deviceSalt)).apply()
            }
            prefs.edit().putBoolean("locked", false).apply()
            _isLocked.value = false
            _isAdminUnlocked.value = true
            Analytics.track(AnalyticsEventType.OPS, "admin_unlock")
        }
        result
    }

    private fun persistLockoutState(state: KioskLockoutState) {
        check(
            prefs.edit()
                .putInt("failed_attempts", state.failedAttempts)
                .putInt("lockout_stage", state.lockoutStage)
                .putLong("locked_until", state.lockedUntilMillis)
                .commit()
        ) { "Could not persist kiosk PIN lockout state" }
        _failedAttempts.value = state.failedAttempts
        _lockedUntil.value = state.lockedUntilMillis
    }

    private fun hasAdminAuthorization(): Boolean =
        !_isLocked.value && (storedPin.isEmpty() || _isAdminUnlocked.value)

    fun performAdminAction(action: () -> Unit) {
        if (hasAdminAuthorization()) action()
    }

    fun showPinUnlockDialog() {
        if (storedPin.isNotEmpty() && !hasAdminAuthorization()) _showPinUnlock.value = true
    }
    fun hidePinUnlockDialog() { _showPinUnlock.value = false }
    fun showSettingsDialog() {
        if (hasAdminAuthorization()) _showSettings.value = true
    }
    fun hideSettingsDialog() { _showSettings.value = false }
}


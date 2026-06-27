package com.example.tavattendance.screens.kiosk

import android.app.Application
import android.content.Context
import android.provider.Settings.Secure
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.KioskEntry
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

// ---------------------------------------------------------------------------
// PIN hashing helpers
// ---------------------------------------------------------------------------

/**
 * Hash a PIN using PBKDF2-SHA256 with 10,000 iterations and the device salt.
 * Output format: "v2:<64 hex chars>" (32-byte / 256-bit derived key).
 *
 * Matches iOS: CCKeyDerivationPBKDF / kCCPBKDF2 / kCCPRFHmacAlgSHA256 /
 *   10_000 iterations / 32-byte output / "v1:" prefix (iOS calls it v1 for
 *   its PBKDF2; Android uses "v2:" to distinguish from the old SHA-256 "v1:").
 *
 * NOTE: iOS writes "v1:" for PBKDF2 hashes. Android previously wrote "v1:" for
 * plain-SHA-256 hashes. To avoid a collision the Android PBKDF2 format uses
 * "v2:" so migration code can tell them apart.
 */
private fun hashPinPbkdf2(pin: String, salt: String): String {
    val saltBytes = salt.toByteArray(Charsets.UTF_8)
    val spec = PBEKeySpec(pin.toCharArray(), saltBytes, 10_000, 256)
    val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
    val derived = factory.generateSecret(spec).encoded
    spec.clearPassword()
    return "v2:" + derived.joinToString("") { "%02x".format(it) }
}

/**
 * Legacy hash: single-round SHA-256 over "$pin:$salt" (the original Android
 * implementation). Stored with prefix "v1:".
 */
private fun hashPinLegacy(pin: String, salt: String): String {
    val md = MessageDigest.getInstance("SHA-256")
    val digest = md.digest("$pin:$salt".toByteArray(Charsets.UTF_8))
    return "v1:" + digest.joinToString("") { "%02x".format(it) }
}

/**
 * Constant-time comparison for hash strings.
 */
private fun secureEquals(a: String, b: String): Boolean =
    MessageDigest.isEqual(a.toByteArray(Charsets.UTF_8), b.toByteArray(Charsets.UTF_8))

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

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

    val failedAttempts = _failedAttempts.asStateFlow()
    val lockedUntil = _lockedUntil.asStateFlow()

    // Persisted kiosk settings
    val storedPin: String get() = prefs.getString("pin", "") ?: ""

    // MAINT-10: back isLocked with a StateFlow so Compose recomposes on change.
    private val _isLocked = MutableStateFlow(prefs.getBoolean("locked", false))
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

    // MAINT-10: derived StateFlow for isAdminMode — Compose will recompose
    // whenever isLocked or isAdminUnlocked changes.
    val isAdminMode = combine(_isAdminUnlocked, _isLocked) { adminUnlocked, locked ->
        !locked && (storedPin.isEmpty() || adminUnlocked)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, !_isLocked.value && (storedPin.isEmpty() || _isAdminUnlocked.value))

    init { loadEntries() }

    fun loadEntries() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching { _entries.value = AttendanceService.fetchKioskEntries() }
                .onFailure { e ->
                    android.util.Log.e("GlobalKioskVM", "Failed to load kiosk entries", e)
                    _snackbarMessage.value = "Failed to load students: ${e.localizedMessage ?: e.javaClass.simpleName}"
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
        if (entry.studentId in _pendingIds.value) return
        _pendingIds.value = _pendingIds.value + entry.studentId

        // SP-06: apply optimistic UI update before the suspend call, then
        // surface any error via snackbarMessage on failure.
        viewModelScope.launch {
            runCatching {
                when (action) {
                    KioskAction.SignIn -> {
                        AttendanceService.markKioskSignIn(entry)
                        val worstStatus = computeSignInStatus(entry)
                        updateEntry(entry.studentId, worstStatus)
                    }
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
                android.util.Log.e("GlobalKioskVM", "Action $action failed for ${entry.studentId}", e)
                _snackbarMessage.value = "Action failed: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _pendingIds.value = _pendingIds.value - entry.studentId
        }
    }

    private fun updateEntry(studentId: String, status: AttendanceStatus) {
        _entries.value = _entries.value.map { e ->
            if (e.studentId == studentId) e.copy(status = status, markedAt = java.time.Instant.now().toString())
            else e
        }
    }

    private fun computeSignInStatus(entry: KioskEntry): AttendanceStatus {
        val now = Date()
        for (session in entry.sessions) {
            if (session.startedAt != null) {
                val startedAt = runCatching {
                    Date(java.time.Instant.parse(session.startedAt).toEpochMilli())
                }.getOrNull()
                if (startedAt != null && now.after(startedAt)) return AttendanceStatus.late
            } else if (session.scheduleTime != null) {
                val parts = session.scheduleTime.split(":").mapNotNull { it.toIntOrNull() }
                if (parts.size >= 2) {
                    val cal = Calendar.getInstance()
                    cal.set(Calendar.HOUR_OF_DAY, parts[0])
                    cal.set(Calendar.MINUTE, parts[1])
                    cal.set(Calendar.SECOND, 0)
                    if (now.after(cal.time)) return AttendanceStatus.late
                }
            }
        }
        return AttendanceStatus.present
    }

    // -----------------------------------------------------------------------
    // PIN management  (SEC-01 + SEC-02)
    // -----------------------------------------------------------------------

    private val deviceSalt: String
        get() = Secure.getString(getApplication<Application>().contentResolver, Secure.ANDROID_ID)
            ?: "tava-kiosk-fallback"

    /** Hash using the new PBKDF2 scheme (v2: prefix). */
    fun hashPin(pin: String): String = hashPinPbkdf2(pin, deviceSalt)

    /**
     * Set the PIN.  Always stores a v2: PBKDF2 hash going forward.
     */
    fun setPin(pin: String) {
        prefs.edit().putString("pin", hashPin(pin)).apply()
    }

    fun clearPin() {
        prefs.edit().remove("pin").putBoolean("locked", false).apply()
        _isLocked.value = false
        _isAdminUnlocked.value = true
        // Clear any lockout state when the PIN is removed.
        persistFailedAttempts(0, 0L)
    }

    /** MAINT-10: update both SharedPreferences and the backing StateFlow. */
    fun lockKiosk() {
        prefs.edit().putBoolean("locked", true).apply()
        _isLocked.value = true
        _isAdminUnlocked.value = false
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
     * SEC-02: failed attempt counter is read from / written to SharedPreferences
     *         so it survives rotation and back-press.
     *
     * Returns true on success.
     */
    fun tryUnlock(pin: String): Boolean {
        val stored = storedPin
        if (stored.isEmpty()) return false

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

        if (matches) {
            // Re-hash with PBKDF2 if the stored value used an older scheme.
            if (!stored.startsWith("v2:")) {
                prefs.edit().putString("pin", hashPinPbkdf2(pin, deviceSalt)).apply()
            }
            prefs.edit().putBoolean("locked", false).apply()
            _isLocked.value = false
            _isAdminUnlocked.value = true
            // Reset lockout on successful unlock.
            persistFailedAttempts(0, 0L)
        }
        return matches
    }

    /** SEC-02: record a failed attempt and compute lockout if threshold reached. */
    fun recordFailedAttempt() {
        val attempts = _failedAttempts.value + 1
        val until = if (attempts >= 5) System.currentTimeMillis() + 30_000L else _lockedUntil.value
        val resetAttempts = if (attempts >= 5) 0 else attempts
        persistFailedAttempts(resetAttempts, until)
    }

    private fun persistFailedAttempts(attempts: Int, until: Long) {
        prefs.edit()
            .putInt("failed_attempts", attempts)
            .putLong("locked_until", until)
            .apply()
        _failedAttempts.value = attempts
        _lockedUntil.value = until
    }

    fun showPinUnlockDialog() { _showPinUnlock.value = true }
    fun hidePinUnlockDialog() { _showPinUnlock.value = false }
    fun showSettingsDialog() { _showSettings.value = true }
    fun hideSettingsDialog() { _showSettings.value = false }
}

enum class KioskAction { SignIn, MarkPresent, MarkLate, MarkAbsent, MarkNotHere }

// ---------------------------------------------------------------------------
// Composable screen
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlobalKioskScreen(vm: GlobalKioskViewModel = viewModel()) {
    val entries by vm.entries.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val pendingIds by vm.pendingIds.collectAsState()
    val isAdminUnlocked by vm.isAdminUnlocked.collectAsState()
    val showPinUnlock by vm.showPinUnlock.collectAsState()
    val showSettings by vm.showSettings.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()

    // MAINT-10: collect StateFlow so Compose recomposes when lock state changes.
    val isLocked by vm.isLocked.collectAsState()
    val isAdminMode by vm.isAdminMode.collectAsState()

    // Study Space (migration 015): flag-gated entry to the internal drop-in tracker.
    val featureFlags by FeatureFlags.flags.collectAsState()
    val studySpaceEnabled = featureFlags[FeatureFlags.STUDY_SPACE_TRACKING] == true
    var showStudySpace by remember { mutableStateOf(false) }

    val attending = entries.count { it.isAttending }
    val today = SimpleDateFormat("EEEE, MMMM d, yyyy", Locale.US).format(Date())

    // SP-06: Snackbar host for surfacing errors.
    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(snackbarMessage) {
        snackbarMessage?.let { msg ->
            snackbarHostState.showSnackbar(message = msg, duration = SnackbarDuration.Short)
            vm.clearSnackbar()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(innerPadding)
        ) {
            Column {
                // Header
                Surface(shadowElevation = 2.dp) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("Sign In", style = MaterialTheme.typography.headlineLarge)
                                if (isAdminMode) {
                                    Spacer(Modifier.width(8.dp))
                                    Surface(
                                        shape = MaterialTheme.shapes.extraSmall,
                                        color = MaterialTheme.colorScheme.tertiary
                                    ) {
                                        Text(
                                            "ADMIN",
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onTertiary,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                            Text(today, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (entries.isNotEmpty()) {
                            Text(
                                "$attending / ${entries.size} attended",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.width(16.dp))
                        }
                        if (isAdminMode && studySpaceEnabled) {
                            TextButton(onClick = { showStudySpace = true }) {
                                Text("Study Space")
                            }
                        }
                        IconButton(
                            onClick = {
                                if (isLocked) vm.showPinUnlockDialog()
                                else vm.showSettingsDialog()
                            }
                        ) {
                            Icon(
                                if (isLocked) Icons.Default.Lock else Icons.Default.Settings,
                                contentDescription = if (isLocked) "Unlock kiosk" else "Kiosk settings"
                            )
                        }
                    }
                }

                when {
                    isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                    entries.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            "No classes scheduled today.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(32.dp)
                        )
                    }
                    else -> LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 160.dp),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(entries, key = { it.studentId }) { entry ->
                            KioskCard(
                                entry = entry,
                                isPending = entry.studentId in pendingIds,
                                isAdminMode = isAdminMode,
                                onTap = { vm.onCardTap(entry) },
                                onAction = { action -> vm.handleAction(entry, action) }
                            )
                        }
                    }
                }
            }

            if (showPinUnlock) {
                PinUnlockOverlay(
                    failedAttempts = vm.failedAttempts,
                    lockedUntil = vm.lockedUntil,
                    onDismiss = { vm.hidePinUnlockDialog() },
                    onAttempt = { pin -> vm.tryUnlock(pin) },
                    onRecordFailedAttempt = { vm.recordFailedAttempt() }
                )
            }

            if (showSettings) {
                KioskSettingsSheet(vm = vm, onDismiss = { vm.hideSettingsDialog() })
            }

            if (showStudySpace) {
                StudySpaceScreen(onDismiss = { showStudySpace = false })
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Kiosk card  (A11Y-04)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KioskCard(
    entry: KioskEntry,
    isPending: Boolean,
    isAdminMode: Boolean,
    onTap: () -> Unit,
    onAction: (KioskAction) -> Unit
) {
    val statusColor: Color = when (entry.status) {
        AttendanceStatus.present -> Color(0xFF34C759)
        AttendanceStatus.late -> Color(0xFFFF9500)
        AttendanceStatus.absent -> Color(0xFFFF3B30)
        AttendanceStatus.excused, null -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
    }

    val statusLabel = when (entry.status) {
        AttendanceStatus.present -> "On Time"
        AttendanceStatus.late -> "Late"
        AttendanceStatus.absent -> "Absent"
        AttendanceStatus.excused -> "Not Here"
        null -> "Not signed in"
    }

    val canTap = entry.status == null || entry.status == AttendanceStatus.excused ||
            (isAdminMode && (entry.status == AttendanceStatus.late || entry.status == AttendanceStatus.absent))

    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    DropdownMenuCard(
        enabled = !isPending,
        canTap = canTap,
        onTap = onTap,
        contextMenuItems = buildList {
            if (isAdminMode) {
                if (entry.status != AttendanceStatus.late && entry.status != AttendanceStatus.absent) {
                    add("Mark as Late" to KioskAction.MarkLate)
                }
                if (entry.status == AttendanceStatus.late || entry.status == AttendanceStatus.present) {
                    add("Mark as Not Here" to KioskAction.MarkNotHere)
                }
                if (entry.status != AttendanceStatus.present && entry.status != null && entry.status != AttendanceStatus.excused) {
                    add("Mark as On Time" to KioskAction.MarkPresent)
                }
                if (entry.status != AttendanceStatus.absent) {
                    add("Mark as Absent" to KioskAction.MarkAbsent)
                }
            }
        },
        onMenuAction = onAction
    ) {
        Card(
            modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
        ) {
            Box(modifier = Modifier.fillMaxSize().padding(12.dp), contentAlignment = Alignment.Center) {
                if (isPending) {
                    CircularProgressIndicator()
                } else {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        // A11Y-04: status indicator with contentDescription so screen readers
                        // convey meaning without relying solely on colour.
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = statusColor,
                            modifier = Modifier
                                .size(12.dp)
                                .semantics { contentDescription = "${entry.fullName}: $statusLabel" }
                        ) {}
                        Spacer(Modifier.height(8.dp))
                        Text(
                            entry.fullName,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                            maxLines = 2
                        )
                        if (entry.status != null) {
                            Spacer(Modifier.height(4.dp))
                            Text(statusLabel, style = MaterialTheme.typography.labelSmall, color = statusColor)
                            if (entry.status != AttendanceStatus.excused && entry.markedAt != null) {
                                val markedDate = runCatching {
                                    Date(java.time.Instant.parse(entry.markedAt).toEpochMilli())
                                }.getOrNull()
                                markedDate?.let {
                                    Text(
                                        timeFmt.format(it),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            if (isAdminMode && entry.status != AttendanceStatus.present && entry.status != AttendanceStatus.excused) {
                                Text(
                                    "Tap → On Time",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// DropdownMenuCard
// ---------------------------------------------------------------------------

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DropdownMenuCard(
    enabled: Boolean,
    canTap: Boolean,
    onTap: () -> Unit,
    contextMenuItems: List<Pair<String, KioskAction>>,
    onMenuAction: (KioskAction) -> Unit,
    content: @Composable () -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                enabled = enabled,
                onClick = {
                    if (canTap) onTap()
                    else if (contextMenuItems.isNotEmpty()) menuExpanded = true
                },
                onLongClick = { if (contextMenuItems.isNotEmpty()) menuExpanded = true }
            )
    ) {
        content()
        if (contextMenuItems.isNotEmpty()) {
            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                contextMenuItems.forEach { (label, action) ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                label,
                                color = if (action == KioskAction.MarkAbsent)
                                    MaterialTheme.colorScheme.error
                                else
                                    MaterialTheme.colorScheme.onSurface
                            )
                        },
                        onClick = { onMenuAction(action); menuExpanded = false }
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Kiosk settings sheet
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KioskSettingsSheet(vm: GlobalKioskViewModel, onDismiss: () -> Unit) {
    var showPinSetup by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Kiosk Settings", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(16.dp))

            if (vm.storedPin.isEmpty()) {
                Text("No PIN set — kiosk is always in admin mode", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { showPinSetup = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Set Kiosk PIN…")
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(shape = MaterialTheme.shapes.extraSmall, color = Color(0xFF34C759), modifier = Modifier.size(10.dp)) {}
                    Spacer(Modifier.width(8.dp))
                    Text("PIN configured")
                }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { showPinSetup = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Change PIN…")
                }
                Spacer(Modifier.height(4.dp))
                Button(onClick = { vm.lockKiosk(); onDismiss() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Lock Kiosk Now")
                }
                Spacer(Modifier.height(4.dp))
                OutlinedButton(
                    onClick = { vm.clearPin(); onDismiss() },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) {
                    Text("Remove PIN")
                }
            }
            Spacer(Modifier.height(32.dp))
        }
    }

    if (showPinSetup) {
        PinSetupDialog(
            onDismiss = { showPinSetup = false },
            onSave = { pin -> vm.setPin(pin); showPinSetup = false }
        )
    }
}

// ---------------------------------------------------------------------------
// PIN setup dialog
// ---------------------------------------------------------------------------

@Composable
private fun PinSetupDialog(onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var step by remember { mutableIntStateOf(1) }
    var firstPin by remember { mutableStateOf("") }
    var secondPin by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }

    val current = if (step == 1) firstPin else secondPin

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (step == 1) "Enter new PIN" else "Confirm PIN") },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    repeat(4) { i ->
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = if (current.length > i) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                            modifier = Modifier.size(18.dp)
                        ) {}
                    }
                }
                if (error.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.height(16.dp))
                NumberPad(
                    onDigit = { d ->
                        error = ""
                        if (step == 1) {
                            if (firstPin.length < 4) {
                                firstPin += d
                                if (firstPin.length == 4) step = 2
                            }
                        } else {
                            if (secondPin.length < 4) {
                                secondPin += d
                                if (secondPin.length == 4) {
                                    if (firstPin == secondPin) onSave(firstPin)
                                    else { error = "PINs don't match"; firstPin = ""; secondPin = ""; step = 1 }
                                }
                            }
                        }
                    },
                    onDelete = {
                        error = ""
                        if (step == 2) { if (secondPin.isEmpty()) step = 1 else secondPin = secondPin.dropLast(1) }
                        else if (firstPin.isNotEmpty()) firstPin = firstPin.dropLast(1)
                    }
                )
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

// ---------------------------------------------------------------------------
// PIN unlock overlay  (SEC-02: reads/writes lockout state from ViewModel prefs)
// ---------------------------------------------------------------------------

@Composable
private fun PinUnlockOverlay(
    failedAttempts: kotlinx.coroutines.flow.StateFlow<Int>,
    lockedUntil: kotlinx.coroutines.flow.StateFlow<Long>,
    onDismiss: () -> Unit,
    onAttempt: (String) -> Boolean,
    onRecordFailedAttempt: () -> Unit
) {
    val failedAttemptsVal by failedAttempts.collectAsState()
    val lockedUntilVal by lockedUntil.collectAsState()

    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var secondsRemaining by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        while (true) {
            val remaining = (lockedUntilVal - System.currentTimeMillis()) / 1000
            secondsRemaining = if (remaining > 0) remaining.toInt() else 0
            kotlinx.coroutines.delay(1000)
        }
    }

    // Keep secondsRemaining updated when lockedUntil changes (e.g. after a
    // failed attempt that triggers lockout).
    LaunchedEffect(lockedUntilVal) {
        val remaining = (lockedUntilVal - System.currentTimeMillis()) / 1000
        secondsRemaining = if (remaining > 0) remaining.toInt() else 0
    }

    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.78f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(32.dp),
            modifier = Modifier.padding(48.dp)
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.Lock,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(56.dp)
                )
                Spacer(Modifier.height(8.dp))
                Text("Admin Access", style = MaterialTheme.typography.headlineLarge, color = Color.White)
                val isLockedOut = System.currentTimeMillis() < lockedUntilVal
                Text(
                    if (isLockedOut) "Too many attempts" else "Enter PIN to unlock",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.7f)
                )
            }

            val isLockedOut = System.currentTimeMillis() < lockedUntilVal
            if (isLockedOut) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "Try again in ${secondsRemaining}s",
                        style = MaterialTheme.typography.titleLarge,
                        color = Color(0xFFFF9500)
                    )
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = onDismiss) { Text("Cancel", color = Color.White.copy(alpha = 0.7f)) }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    repeat(4) { i ->
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = if (entered.length > i) Color.White else Color.White.copy(alpha = 0.3f),
                            modifier = Modifier.size(18.dp)
                        ) {}
                    }
                }
                if (error.isNotEmpty()) {
                    Text(error, color = Color(0xFFFF3B30), style = MaterialTheme.typography.bodySmall)
                }
                NumberPad(
                    tint = Color.White,
                    leadingButton = {
                        TextButton(onClick = onDismiss) {
                            Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                        }
                    },
                    onDigit = { d ->
                        if (System.currentTimeMillis() >= lockedUntilVal && entered.length < 4) {
                            error = ""
                            entered += d
                            if (entered.length == 4) {
                                val success = onAttempt(entered)
                                if (success) {
                                    onDismiss()
                                } else {
                                    onRecordFailedAttempt()
                                    val isNowLockedOut = System.currentTimeMillis() < lockedUntilVal
                                    if (!isNowLockedOut) {
                                        val left = 5 - (failedAttemptsVal)
                                        error = if (left > 0)
                                            "Incorrect PIN — $left attempt${if (left == 1) "" else "s"} left"
                                        else
                                            "Incorrect PIN"
                                    }
                                    entered = ""
                                }
                            }
                        }
                    },
                    onDelete = { if (entered.isNotEmpty()) entered = entered.dropLast(1) }
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Number pad
// ---------------------------------------------------------------------------

@Composable
private fun NumberPad(
    tint: Color = MaterialTheme.colorScheme.primary,
    leadingButton: (@Composable () -> Unit)? = null,
    onDigit: (String) -> Unit,
    onDelete: () -> Unit
) {
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { digit ->
                    NumKey(digit, tint) { onDigit(digit) }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (leadingButton != null) {
                Box(modifier = Modifier.size(72.dp), contentAlignment = Alignment.Center) {
                    leadingButton()
                }
            } else {
                Spacer(Modifier.size(72.dp))
            }
            NumKey("0", tint) { onDigit("0") }
            TextButton(onClick = onDelete, modifier = Modifier.size(72.dp)) {
                Text("⌫", style = MaterialTheme.typography.titleLarge, color = tint)
            }
        }
    }
}

@Composable
private fun NumKey(digit: String, tint: Color, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = MaterialTheme.shapes.extraLarge,
        color = tint.copy(alpha = 0.15f),
        modifier = Modifier.size(72.dp)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(digit, style = MaterialTheme.typography.headlineMedium, color = tint)
        }
    }
}

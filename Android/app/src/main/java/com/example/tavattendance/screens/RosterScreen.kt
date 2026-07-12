package com.example.tavattendance.screens

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.RosterEntry
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import com.example.tavattendance.data.store.PendingAttendanceStore
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.*

class RosterViewModel(app: Application) : AndroidViewModel(app) {
    private val pendingStore = PendingAttendanceStore(app)

    private val _roster = MutableStateFlow<List<RosterEntry>>(emptyList())
    val roster = _roster.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _isSaving = MutableStateFlow(false)
    val isSaving = _isSaving.asStateFlow()

    private val _isEndingClass = MutableStateFlow(false)
    val isEndingClass = _isEndingClass.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    // Session notes (flag `session_notes`): current saved value + in-flight save state.
    private val _sessionNotes = MutableStateFlow<String?>(null)
    val sessionNotes = _sessionNotes.asStateFlow()

    private val _isSavingNotes = MutableStateFlow(false)
    val isSavingNotes = _isSavingNotes.asStateFlow()

    fun clearSnackbar() { _snackbarMessage.value = null }

    // Optimistic local overrides: studentId → status
    private val _localStatus = MutableStateFlow<Map<String, AttendanceStatus>>(emptyMap())
    val localStatus = _localStatus.asStateFlow()

    private val _localMarkedAt = MutableStateFlow<Map<String, Date>>(emptyMap())
    val localMarkedAt = _localMarkedAt.asStateFlow()

    val isOnline: StateFlow<Boolean> = callbackFlow {
        val cm = app.getSystemService(ConnectivityManager::class.java)
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) { trySend(true) }
            override fun onLost(n: Network) { trySend(false) }
        }
        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
        cm.registerNetworkCallback(req, cb)
        val current = cm.activeNetwork?.let {
            cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } ?: false
        trySend(current)
        awaitClose { cm.unregisterNetworkCallback(cb) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    private var sessionId: String = ""

    fun init(sessionId: String) {
        this.sessionId = sessionId
        loadRoster()
        loadSessionNotes()
        viewModelScope.launch {
            isOnline.collect { connected ->
                if (connected) syncPending()
            }
        }
    }

    private fun loadSessionNotes() {
        viewModelScope.launch {
            runCatching { AttendanceService.fetchSessionNotes(sessionId) }
                .onSuccess { _sessionNotes.value = it }
                .onFailure { android.util.Log.e("Roster", "loadSessionNotes failed: ${it.message}", it) }
        }
    }

    fun saveSessionNotes(text: String, onDone: () -> Unit) {
        viewModelScope.launch {
            _isSavingNotes.value = true
            val trimmed = text.trim().ifEmpty { null }
            runCatching { AttendanceService.updateSessionNotes(sessionId, trimmed) }
                .onSuccess { _sessionNotes.value = trimmed; onDone() }
                .onFailure { e ->
                    android.util.Log.e("Roster", "saveSessionNotes failed: ${e.message}", e)
                    _snackbarMessage.value = "Failed to save session notes: ${e.localizedMessage ?: e.javaClass.simpleName}"
                }
            _isSavingNotes.value = false
        }
    }

    fun loadRoster() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            runCatching { AttendanceService.fetchRoster(sessionId) }
                .onSuccess { _roster.value = it }
                .onFailure { e ->
                    android.util.Log.e("Roster", "loadRoster failed: ${e.message}", e)
                    _loadError.value = e.localizedMessage ?: "Failed to load roster"
                }
            _isLoading.value = false
        }
    }

    fun markAttendance(entry: RosterEntry, status: AttendanceStatus) {
        // Optimistic update
        _localStatus.value = _localStatus.value + (entry.studentId to status)
        _localMarkedAt.value = _localMarkedAt.value + (entry.studentId to Date())

        viewModelScope.launch {
            if (isOnline.value) {
                runCatching {
                    AttendanceService.markAttendance(
                        sessionId = sessionId,
                        studentId = entry.studentId,
                        status = status
                    )
                    // PERF-04: trust the optimistic override instead of re-fetching the
                    // whole roster on every tap. The override stays until loadRoster()
                    // is called again (reopen / pull-to-refresh).
                }.onFailure {
                    pendingStore.add(sessionId, entry.studentId, status, null)
                }
            } else {
                pendingStore.add(sessionId, entry.studentId, status, null)
            }
        }
    }

    // PROD-03: students with no status yet (server, pending, or local override).
    fun unmarkedEntries(): List<RosterEntry> = _roster.value.filter { effectiveStatus(it) == null }

    fun markAllUnmarkedAbsent() {
        for (entry in unmarkedEntries()) {
            markAttendance(entry, AttendanceStatus.absent)
        }
    }

    fun endClass(onComplete: () -> Unit) {
        viewModelScope.launch {
            _isEndingClass.value = true
            runCatching {
                AttendanceService.endSession(sessionId)
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { onComplete() }
            }.onFailure { e ->
                android.util.Log.e("Roster", "endClass failed: ${e.message}", e)
                _snackbarMessage.value = "Failed to end class: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isEndingClass.value = false
        }
    }

    // Syncs ALL pending records (not just this session's) — pending marks made in a session
    // that isn't reopened online would otherwise never sync.
    fun syncPending() {
        viewModelScope.launch {
            val unsynced = pendingStore.allPending()
            if (unsynced.isEmpty()) return@launch
            _isSaving.value = true
            runCatching {
                val result = AttendanceService.syncPending(unsynced)
                // Only mark the batch fully synced when the server accounted for every
                // record (synced + skipped); a mismatch means some were blocked (ended
                // session) and must stay pending — we can't tell which ones from the
                // aggregate counts, so leave the whole batch in the store rather than
                // silently drop the blocked ones.
                if (result.synced + result.skipped == unsynced.size) {
                    pendingStore.markSynced(unsynced.map { it.clientMutationId }.toSet())
                    for (r in unsynced.filter { it.sessionId == sessionId }) {
                        _localStatus.value = _localStatus.value - r.studentId
                        _localMarkedAt.value = _localMarkedAt.value - r.studentId
                    }
                    _roster.value = AttendanceService.fetchRoster(sessionId)
                }
                if (result.blockedEndedSession > 0) {
                    _snackbarMessage.value =
                        "${result.blockedEndedSession} mark${if (result.blockedEndedSession == 1) "" else "s"} rejected — session already ended."
                }
            }.onFailure { e ->
                android.util.Log.e("Roster", "syncPending failed: ${e.message}", e)
                _snackbarMessage.value = "Failed to sync attendance: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isSaving.value = false
        }
    }

    fun effectiveStatus(entry: RosterEntry): AttendanceStatus? {
        _localStatus.value[entry.studentId]?.let { return it }
        pendingStore.allPending().firstOrNull {
            it.studentId == entry.studentId && it.sessionId == sessionId
        }?.let { return it.status }
        return entry.status
    }

    fun isPending(entry: RosterEntry): Boolean =
        pendingStore.allPending().any { it.studentId == entry.studentId && it.sessionId == sessionId }

    fun hasPendingUnsynced(): Boolean =
        pendingStore.allPending().any { it.sessionId == sessionId }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RosterScreen(
    sessionId: String,
    sessionDate: String,
    className: String,
    onBack: () -> Unit,
    vm: RosterViewModel = viewModel()
) {
    LaunchedEffect(sessionId) { vm.init(sessionId) }

    val roster by vm.roster.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val isSaving by vm.isSaving.collectAsState()
    val isOnline by vm.isOnline.collectAsState()
    val localStatus by vm.localStatus.collectAsState()
    val localMarkedAt by vm.localMarkedAt.collectAsState()
    val loadError by vm.loadError.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()

    val flags by FeatureFlags.flags.collectAsState()
    val sessionNotesEnabled = flags[FeatureFlags.SESSION_NOTES] == true
    val sessionNotes by vm.sessionNotes.collectAsState()
    val isSavingNotes by vm.isSavingNotes.collectAsState()
    var showSessionNotes by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(snackbarMessage) {
        snackbarMessage?.let { msg ->
            snackbarHostState.showSnackbar(message = msg, duration = SnackbarDuration.Long)
            vm.clearSnackbar()
        }
    }

    var selectedStudent by remember { mutableStateOf<RosterEntry?>(null) }
    var showEndConfirm by remember { mutableStateOf(false) }
    var showMarkAbsentConfirm by remember { mutableStateOf(false) }  // PROD-03

    val isEndingClass by vm.isEndingClass.collectAsState()

    val prettyFmt = SimpleDateFormat("MMM d, yyyy", Locale.US)
    val isoFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    fun formatDate(iso: String): String = runCatching {
        prettyFmt.format(isoFmt.parse(iso)!!)
    }.getOrDefault(iso)

    // PROD-03: count students still without a status (reads roster + local overrides).
    val unmarkedCount = roster.count { vm.effectiveStatus(it) == null }

    if (showMarkAbsentConfirm) {
        AlertDialog(
            onDismissRequest = { showMarkAbsentConfirm = false },
            title = { Text("Mark Remaining as Absent") },
            text = { Text("$unmarkedCount student${if (unmarkedCount == 1) "" else "s"} have no status yet. Mark them all as Absent?") },
            confirmButton = {
                TextButton(onClick = {
                    showMarkAbsentConfirm = false
                    vm.markAllUnmarkedAbsent()
                }) {
                    Text("Mark $unmarkedCount Absent", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showMarkAbsentConfirm = false }) { Text("Cancel") }
            }
        )
    }

    if (showEndConfirm) {
        AlertDialog(
            onDismissRequest = { showEndConfirm = false },
            title = { Text("End Class") },
            text = { Text("Students can no longer be marked after the class ends. You can resume from the class page.") },
            confirmButton = {
                TextButton(onClick = {
                    showEndConfirm = false
                    vm.endClass(onBack)
                }) {
                    Text("End Class", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showEndConfirm = false }) { Text("Cancel") }
            }
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("${formatDate(sessionDate)} · $className") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (sessionNotesEnabled) {
                        IconButton(onClick = { showSessionNotes = true }) {
                            Icon(Icons.Default.Edit, contentDescription = "Session notes")
                        }
                    }
                    if (!isOnline) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = "Offline",
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(end = 8.dp)
                        )
                    }
                    if (isOnline && vm.hasPendingUnsynced()) {
                        IconButton(onClick = { vm.syncPending() }, enabled = !isSaving) {
                            Icon(Icons.Default.Refresh, contentDescription = "Sync")
                        }
                    }
                    if (unmarkedCount > 0 && !isEndingClass) {
                        TextButton(onClick = { showMarkAbsentConfirm = true }, enabled = !isSaving) {
                            Text("Absent rest")
                        }
                    }
                    if (isEndingClass) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp).padding(end = 8.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        TextButton(
                            onClick = { showEndConfirm = true },
                            enabled = !isEndingClass
                        ) {
                            Text("End Class", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            )
        }
    ) { padding ->
        when {
            isLoading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            loadError != null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(16.dp)) {
                    Text(loadError!!, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { vm.loadRoster() }) { Text("Retry") }
                }
            }
            roster.isEmpty() -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("No students enrolled.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(roster, key = { it.studentId }) { entry ->
                    val status = vm.effectiveStatus(entry)
                    val pending = vm.isPending(entry)
                    val markedAt = localMarkedAt[entry.studentId]
                        ?: entry.markedAt?.let { runCatching { Date(Instant.parse(it).toEpochMilli()) }.getOrNull() }

                    RosterRow(
                        entry = entry,
                        effectiveStatus = status,
                        isPending = pending,
                        markedAt = markedAt,
                        timeFmt = timeFmt,
                        onStatusClick = { newStatus -> vm.markAttendance(entry, newStatus) },
                        onTap = { selectedStudent = entry }
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    selectedStudent?.let { entry ->
        StudentProfileSheet(
            studentId = entry.studentId,
            fullName = entry.fullName,
            onDismiss = { selectedStudent = null }
        )
    }

    if (sessionNotesEnabled && showSessionNotes) {
        SessionNotesDialog(
            initial = sessionNotes ?: "",
            isSaving = isSavingNotes,
            onDismiss = { showSessionNotes = false },
            onSave = { text -> vm.saveSessionNotes(text) { showSessionNotes = false } }
        )
    }
}

@Composable
private fun SessionNotesDialog(
    initial: String,
    isSaving: Boolean,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var text by remember { mutableStateOf(initial) }

    AlertDialog(
        onDismissRequest = { if (!isSaving) onDismiss() },
        title = { Text("Session Notes") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                enabled = !isSaving,
                placeholder = { Text("Notes for this session") }
            )
        },
        confirmButton = {
            if (isSaving) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
            } else {
                TextButton(onClick = { onSave(text) }, enabled = text != initial) {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSaving) { Text("Cancel") }
        }
    )
}

@Composable
private fun RosterRow(
    entry: RosterEntry,
    effectiveStatus: AttendanceStatus?,
    isPending: Boolean,
    markedAt: Date?,
    timeFmt: SimpleDateFormat,
    onStatusClick: (AttendanceStatus) -> Unit,
    onTap: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f).clickable { onTap() }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(entry.fullName, style = MaterialTheme.typography.titleMedium)
                if (isPending) {
                    Spacer(Modifier.width(6.dp))
                    Surface(
                        shape = MaterialTheme.shapes.extraSmall,
                        color = MaterialTheme.colorScheme.tertiary,
                        modifier = Modifier.size(8.dp)
                    ) {}
                }
            }
            if (markedAt != null) {
                Text(
                    text = "Marked ${timeFmt.format(markedAt)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            AttendanceStatus.entries.forEach { status ->
                val isSelected = effectiveStatus == status
                val color = statusColor(status)
                OutlinedButton(
                    onClick = { onStatusClick(status) },
                    modifier = Modifier.size(44.dp, 36.dp),
                    contentPadding = PaddingValues(0.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = if (isSelected) color else Color.Transparent,
                        contentColor = if (isSelected) Color.White else color
                    ),
                    border = ButtonDefaults.outlinedButtonBorder.copy(
                        brush = androidx.compose.ui.graphics.SolidColor(if (isSelected) color else color.copy(alpha = 0.5f))
                    )
                ) {
                    Text(status.name.take(1).uppercase(), style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

fun statusColor(status: AttendanceStatus): Color = when (status) {
    AttendanceStatus.present -> Color(0xFF34C759)
    AttendanceStatus.late -> Color(0xFFFF9500)
    AttendanceStatus.absent -> Color(0xFFFF3B30)
    AttendanceStatus.excused -> Color(0xFF8E8E93)
}

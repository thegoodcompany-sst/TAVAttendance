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
        viewModelScope.launch {
            isOnline.collect { connected ->
                if (connected) syncPending()
            }
        }
    }

    fun loadRoster() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching { _roster.value = AttendanceService.fetchRoster(sessionId) }
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
                    // Remove optimistic override — server confirmed
                    _localStatus.value = _localStatus.value - entry.studentId
                    _localMarkedAt.value = _localMarkedAt.value - entry.studentId
                    // Refresh roster
                    _roster.value = AttendanceService.fetchRoster(sessionId)
                }.onFailure {
                    pendingStore.add(sessionId, entry.studentId, status, null)
                }
            } else {
                pendingStore.add(sessionId, entry.studentId, status, null)
            }
        }
    }

    fun syncPending() {
        viewModelScope.launch {
            val unsynced = pendingStore.allPending().filter { it.sessionId == sessionId }
            if (unsynced.isEmpty()) return@launch
            _isSaving.value = true
            runCatching {
                val (synced, _) = AttendanceService.syncPending(unsynced)
                if (synced > 0) {
                    pendingStore.markSynced(unsynced.map { it.clientMutationId }.toSet())
                    for (r in unsynced) {
                        _localStatus.value = _localStatus.value - r.studentId
                        _localMarkedAt.value = _localMarkedAt.value - r.studentId
                    }
                    _roster.value = AttendanceService.fetchRoster(sessionId)
                }
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

    var selectedStudent by remember { mutableStateOf<RosterEntry?>(null) }

    val prettyFmt = SimpleDateFormat("MMM d, yyyy", Locale.US)
    val isoFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    fun formatDate(iso: String): String = runCatching {
        prettyFmt.format(isoFmt.parse(iso)!!)
    }.getOrDefault(iso)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${formatDate(sessionDate)} · $className") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
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
                }
            )
        }
    ) { padding ->
        when {
            isLoading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
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

package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.Session
import com.example.tavattendance.data.models.TAVClass
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

class SessionListViewModel(app: Application) : AndroidViewModel(app) {
    private val _sessions = MutableStateFlow<List<Session>>(emptyList())
    val sessions = _sessions.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _isStarting = MutableStateFlow(false)
    val isStarting = _isStarting.asStateFlow()

    private val _isEnding = MutableStateFlow(false)
    val isEnding = _isEnding.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    fun clearSnackbar() { _snackbarMessage.value = null }

    private var classId: String = ""
    private var tavClass: TAVClass? = null

    fun init(classId: String) {
        this.classId = classId
        viewModelScope.launch {
            tavClass = AttendanceService.fetchClass(classId)
            loadSessions()
        }
    }

    fun loadSessions() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching { AttendanceService.fetchSessions(classId) }
                .onSuccess { _sessions.value = it }
                .onFailure { e ->
                    android.util.Log.e("SessionList", "fetchSessions failed: ${e.message}", e)
                    _snackbarMessage.value = "Failed to load sessions: ${e.localizedMessage ?: e.javaClass.simpleName}"
                }
            autoEndIfExpired()
            _isLoading.value = false
        }
    }

    private fun autoEndIfExpired() {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val session = _sessions.value.firstOrNull { it.sessionDate == today } ?: return
        if (session.startedAt == null || session.endedAt != null) return
        val endTime = computeScheduledEndTime() ?: return

        val startedAt = runCatching {
            java.time.Instant.parse(session.startedAt).let { Date(it.toEpochMilli()) }
        }.getOrNull() ?: return

        if (startedAt >= endTime || Date() <= endTime) return

        viewModelScope.launch {
            runCatching { AttendanceService.endSession(session.id) }
                .onFailure { e ->
                    android.util.Log.e("SessionList", "autoEndIfExpired failed: ${e.message}", e)
                    _snackbarMessage.value = "Failed to auto-end class: ${e.localizedMessage ?: e.javaClass.simpleName}"
                }
            runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
        }
    }

    private fun computeScheduledEndTime(): Date? {
        val cls = tavClass ?: return null
        val timeStr = cls.scheduleTime ?: return null
        val parts = timeStr.split(":").mapNotNull { it.toIntOrNull() }
        if (parts.size < 2) return null
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, parts[0])
        cal.set(Calendar.MINUTE, parts[1])
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        cal.add(Calendar.MINUTE, cls.durationMinutes)
        return cal.time
    }

    fun startTodayClass(onSessionReady: (Session) -> Unit) {
        viewModelScope.launch {
            _isStarting.value = true
            runCatching {
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                val session = AttendanceService.getOrCreateSession(classId = classId, date = today)
                if (session.startedAt == null) {
                    AttendanceService.startSession(id = session.id)
                }
                runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
                val fresh = _sessions.value.firstOrNull { it.id == session.id } ?: session
                onSessionReady(fresh)
            }.onFailure { e ->
                android.util.Log.e("SessionList", "startTodayClass failed: ${e.message}", e)
                _snackbarMessage.value = "Failed to start class: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isStarting.value = false
        }
    }

    fun resumeTodayClass(session: Session, onSessionReady: (Session) -> Unit) {
        viewModelScope.launch {
            _isStarting.value = true
            runCatching {
                if (session.endedAt != null) {
                    AttendanceService.resumeSession(id = session.id)
                }
                runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
                val fresh = _sessions.value.firstOrNull { it.id == session.id } ?: session
                onSessionReady(fresh)
            }.onFailure { e ->
                android.util.Log.e("SessionList", "resumeTodayClass failed: ${e.message}", e)
                _snackbarMessage.value = "Failed to resume class: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isStarting.value = false
        }
    }

    fun endTodayClass(session: Session) {
        viewModelScope.launch {
            _isEnding.value = true
            runCatching {
                AttendanceService.endSession(id = session.id)
                runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
            }.onFailure { e ->
                android.util.Log.e("SessionList", "endTodayClass failed: ${e.message}", e)
                _snackbarMessage.value = "Failed to end class: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isEnding.value = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionListScreen(
    classId: String,
    className: String,
    isAdmin: Boolean,
    onSessionClick: (Session) -> Unit,
    onManageEnrollment: () -> Unit,
    onManageTutors: () -> Unit,
    onBack: () -> Unit,
    vm: SessionListViewModel = viewModel()
) {
    LaunchedEffect(classId) { vm.init(classId) }

    // Reload when returning from RosterScreen; skip the first ON_RESUME which fires
    // immediately on observer registration (lifecycle catch-up) since init() already loads.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        var isFirst = true
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (isFirst) { isFirst = false } else { vm.loadSessions() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val sessions by vm.sessions.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val isStarting by vm.isStarting.collectAsState()
    val isEnding by vm.isEnding.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(snackbarMessage) {
        snackbarMessage?.let { msg ->
            snackbarHostState.showSnackbar(message = msg, duration = SnackbarDuration.Short)
            vm.clearSnackbar()
        }
    }

    val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    val todaySession = sessions.firstOrNull { it.sessionDate == todayStr }

    val displayFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val prettyFmt = SimpleDateFormat("MMM d, yyyy", Locale.US)
    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    fun formatDate(iso: String): String = runCatching {
        prettyFmt.format(displayFmt.parse(iso)!!)
    }.getOrDefault(iso)

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(className) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (isAdmin) {
                        IconButton(onClick = onManageTutors) {
                            Icon(Icons.Default.Person, contentDescription = "Assign tutors")
                        }
                        IconButton(onClick = onManageEnrollment) {
                            Icon(Icons.Default.Person, contentDescription = "Manage students")
                        }
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                item {
                    TodayClassControls(
                        session = todaySession,
                        isStarting = isStarting,
                        isEnding = isEnding,
                        timeFmt = timeFmt,
                        onStart = { vm.startTodayClass(onSessionClick) },
                        onResume = { session -> vm.resumeTodayClass(session, onSessionClick) },
                        onEnd = { session -> vm.endTodayClass(session) }
                    )
                }

                val pastSessions = sessions.filter { it.sessionDate != todayStr }
                if (pastSessions.isEmpty()) {
                    item {
                        Text(
                            text = "No past sessions yet.",
                            modifier = Modifier.padding(16.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    item {
                        Text(
                            text = "Past Sessions",
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    items(pastSessions, key = { it.id }) { session ->
                        ListItem(
                            headlineContent = { Text(formatDate(session.sessionDate)) },
                            supportingContent = {
                                session.topic?.takeIf { it.isNotBlank() }?.let { Text(it) }
                            },
                            modifier = Modifier.clickable { onSessionClick(session) }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

@Composable
private fun TodayClassControls(
    session: Session?,
    isStarting: Boolean,
    isEnding: Boolean,
    timeFmt: SimpleDateFormat,
    onStart: () -> Unit,
    onResume: (Session) -> Unit,
    onEnd: (Session) -> Unit
) {
    val busy = isStarting || isEnding

    when {
        session == null || session.startedAt == null -> {
            // Not yet started
            TodayActionCard(
                title = "Start Today's Class",
                subtitle = null,
                color = if (busy) MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
                        else MaterialTheme.colorScheme.primary,
                showSpinner = isStarting,
                enabled = !busy,
                onClick = onStart
            )
        }
        session.endedAt != null -> {
            // Ended — allow resume
            val endedDate = runCatching {
                java.time.Instant.parse(session.endedAt).let { Date(it.toEpochMilli()) }
            }.getOrNull()
            TodayActionCard(
                title = "Resume Class",
                subtitle = endedDate?.let { "Ended ${timeFmt.format(it)}" },
                color = if (busy) MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
                        else MaterialTheme.colorScheme.primary,
                showSpinner = isStarting,
                enabled = !busy,
                onClick = { onResume(session) }
            )
        }
        else -> {
            // In progress — resume or end
            val startedDate = runCatching {
                java.time.Instant.parse(session.startedAt).let { Date(it.toEpochMilli()) }
            }.getOrNull()
            TodayActionCard(
                title = "Resume Class",
                subtitle = startedDate?.let { "Started ${timeFmt.format(it)}" },
                color = Color(0xFF34C759),
                showSpinner = isStarting,
                enabled = !busy,
                onClick = { onResume(session) }
            )
            Spacer(Modifier.height(4.dp))
            EndClassRow(
                isEnding = isEnding,
                enabled = !busy,
                onClick = { onEnd(session) }
            )
        }
    }
}

@Composable
private fun TodayActionCard(
    title: String,
    subtitle: String?,
    color: Color,
    showSpinner: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = color),
        onClick = { if (enabled) onClick() }
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium, color = Color.White)
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.85f)
                    )
                }
            }
            if (showSpinner) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
            }
        }
    }
}

@Composable
private fun EndClassRow(isEnding: Boolean, enabled: Boolean, onClick: () -> Unit) {
    var showConfirm by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center
    ) {
        OutlinedButton(
            onClick = { showConfirm = true },
            enabled = enabled && !isEnding,
            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
            border = ButtonDefaults.outlinedButtonBorder.copy(
                brush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.error.copy(alpha = 0.5f))
            )
        ) {
            if (isEnding) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text("Ending…")
            } else {
                Text("End Class")
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("End Class") },
            text = { Text("Students can no longer be marked after the class ends. You can resume from the class page.") },
            confirmButton = {
                TextButton(onClick = { showConfirm = false; onClick() }) {
                    Text("End Class", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) { Text("Cancel") }
            }
        )
    }
}

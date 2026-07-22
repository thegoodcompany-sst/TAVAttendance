package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
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
import com.example.tavattendance.core.Analytics
import com.example.tavattendance.core.AnalyticsEventType
import com.example.tavattendance.core.SafeLog
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.data.models.Session
import com.example.tavattendance.data.models.RetrospectiveSessionRules
import com.example.tavattendance.data.models.TAVClass
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
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

    // Distinguishes "load failed" from "no past sessions yet" so the empty state doesn't
    // mislead when the fetch actually threw.
    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    private val _canManageSessions = MutableStateFlow(false)
    val canManageSessions = _canManageSessions.asStateFlow()

    private val _canOperateToday = MutableStateFlow(false)
    val canOperateToday = _canOperateToday.asStateFlow()

    fun clearSnackbar() { _snackbarMessage.value = null }

    private var classId: String = ""
    private var tavClass: TAVClass? = null

    fun init(classId: String) {
        this.classId = classId
        viewModelScope.launch {
            // A fetchClass failure must not abort the coroutine (which would leave the
            // screen stuck loading); a null class just disables scheduled auto-end.
            tavClass = runCatching { AttendanceService.fetchClass(classId) }.getOrNull()
            _canManageSessions.value = tavClass?.canManageSessions == true
            _canOperateToday.value = tavClass?.canOperateTodaySession == true
            loadSessions()
        }
    }

    fun loadSessions() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            runCatching { AttendanceService.fetchSessions(classId) }
                .onSuccess { _sessions.value = it }
                .onFailure { e ->
                    SafeLog.error("SessionList", "fetchSessions failed", e)
                    _loadError.value = "Failed to load sessions: ${e.localizedMessage ?: e.javaClass.simpleName}"
                }
            autoEndIfExpired()
            _isLoading.value = false
        }
    }

    private fun autoEndIfExpired() {
        if (!_canOperateToday.value) return
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
                    SafeLog.error("SessionList", "autoEndIfExpired failed", e)
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
        if (!_canOperateToday.value) {
            _snackbarMessage.value = "You are not assigned to today's session."
            return
        }
        viewModelScope.launch {
            _isStarting.value = true
            runCatching {
                val session = AttendanceService.getOrCreateTodaySession(classId = classId)
                if (session.startedAt == null) {
                    AttendanceService.startSession(id = session.id)
                }
                Analytics.track(AnalyticsEventType.TAP, "start_session",
                    buildJsonObject { put("screen", "session_list") })
                runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
                val fresh = _sessions.value.firstOrNull { it.id == session.id } ?: session
                onSessionReady(fresh)
            }.onFailure { e ->
                SafeLog.error("SessionList", "startTodayClass failed", e)
                _snackbarMessage.value = "Failed to start class: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isStarting.value = false
        }
    }

    fun openTodayClass(session: Session, onSessionReady: (Session) -> Unit) {
        viewModelScope.launch {
            _isStarting.value = true
            runCatching {
                runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
                val fresh = _sessions.value.firstOrNull { it.id == session.id } ?: session
                onSessionReady(fresh)
            }.onFailure { e ->
                SafeLog.error("SessionList", "openTodayClass failed", e)
                _snackbarMessage.value = "Failed to open class: ${e.localizedMessage ?: e.javaClass.simpleName}"
            }
            _isStarting.value = false
        }
    }

    fun endTodayClass(session: Session) {
        if (!_canOperateToday.value) return
        viewModelScope.launch {
            _isEnding.value = true
            runCatching {
                AttendanceService.endSession(id = session.id)
                Analytics.track(AnalyticsEventType.TAP, "end_session",
                    buildJsonObject { put("screen", "session_list") })
                runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
            }.onFailure { e ->
                SafeLog.error("SessionList", "endTodayClass failed", e)
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
    onHistoricalSessionClick: (Session) -> Unit,
    onAddPastSession: () -> Unit,
    onManageEnrollment: () -> Unit,
    onManageTutors: () -> Unit,
    onBack: () -> Unit,
    vm: SessionListViewModel = viewModel()
) {
    TrackScreen("session_list")
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
    val loadError by vm.loadError.collectAsState()
    val canManageSessions by vm.canManageSessions.collectAsState()
    val canOperateToday by vm.canOperateToday.collectAsState()
    val flags by FeatureFlags.flags.collectAsState()
    val retrospectiveEnabled = flags[FeatureFlags.RETROSPECTIVE_SESSIONS] == true

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
                    if (retrospectiveEnabled && canManageSessions) {
                        IconButton(onClick = onAddPastSession) {
                            Icon(Icons.Default.Add, contentDescription = "Add past session")
                        }
                    }
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
        } else if (loadError != null && sessions.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(24.dp)) {
                    Text(loadError!!, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { vm.loadSessions() }) { Text("Retry") }
                }
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                item {
                    TodayClassControls(
                        session = todaySession,
                        canOperateToday = canOperateToday,
                        isStarting = isStarting,
                        isEnding = isEnding,
                        timeFmt = timeFmt,
                        onStart = { vm.startTodayClass(onSessionClick) },
                        onOpen = { session -> vm.openTodayClass(session, onSessionClick) },
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
                            modifier = Modifier.clickable {
                                if (canManageSessions && RetrospectiveSessionRules.editorEnabled(session, retrospectiveEnabled)) {
                                    onHistoricalSessionClick(session)
                                } else {
                                    onSessionClick(session)
                                }
                            }
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
    canOperateToday: Boolean,
    isStarting: Boolean,
    isEnding: Boolean,
    timeFmt: SimpleDateFormat,
    onStart: () -> Unit,
    onOpen: (Session) -> Unit,
    onEnd: (Session) -> Unit
) {
    val busy = isStarting || isEnding

    when {
        !canOperateToday -> {
            ListItem(
                headlineContent = { Text("Recent substitute access is read-only") },
                supportingContent = { Text("You are not assigned to today's session.") }
            )
        }
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
            // Ended sessions are immutable; allow read-only roster review.
            val endedDate = runCatching {
                java.time.Instant.parse(session.endedAt).let { Date(it.toEpochMilli()) }
            }.getOrNull()
            TodayActionCard(
                title = "View Ended Class",
                subtitle = endedDate?.let { "Ended ${timeFmt.format(it)}" },
                color = if (busy) MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
                        else MaterialTheme.colorScheme.primary,
                showSpinner = isStarting,
                enabled = !busy,
                onClick = { onOpen(session) }
            )
        }
        else -> {
            // In progress — return or end
            val startedDate = runCatching {
                java.time.Instant.parse(session.startedAt).let { Date(it.toEpochMilli()) }
            }.getOrNull()
            TodayActionCard(
                title = "Return to Class",
                subtitle = startedDate?.let { "Started ${timeFmt.format(it)}" },
                color = Color(0xFF34C759),
                showSpinner = isStarting,
                enabled = !busy,
                onClick = { onOpen(session) }
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
            text = { Text("Students can no longer be marked after the class ends. The roster remains available for review.") },
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

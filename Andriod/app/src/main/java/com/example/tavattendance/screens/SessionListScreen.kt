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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.Session
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

    private val _startedSession = MutableStateFlow<Session?>(null)
    val startedSession = _startedSession.asStateFlow()

    private var classId: String = ""

    fun init(classId: String) {
        this.classId = classId
        loadSessions()
    }

    fun loadSessions() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching { _sessions.value = AttendanceService.fetchSessions(classId) }
            _isLoading.value = false
        }
    }

    fun startTodayClass(onSessionReady: (Session) -> Unit) {
        viewModelScope.launch {
            _isStarting.value = true
            runCatching {
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                val session = AttendanceService.getOrCreateSession(classId = classId, date = today)
                AttendanceService.startSession(id = session.id)
                loadSessions()
                onSessionReady(session)
            }.onFailure { e ->
                android.util.Log.e("SessionList", "startTodayClass failed: ${e.message}", e)
            }
            _isStarting.value = false
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

    val sessions by vm.sessions.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val isStarting by vm.isStarting.collectAsState()

    val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    val todaySession = sessions.firstOrNull { it.sessionDate == todayStr }

    val displayFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val prettyFmt = SimpleDateFormat("MMM d, yyyy", Locale.US)
    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    fun formatDate(iso: String): String = runCatching {
        prettyFmt.format(displayFmt.parse(iso)!!)
    }.getOrDefault(iso)

    Scaffold(
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
                // Start Today's Class button
                item {
                    val inProgress = todaySession?.startedAt != null
                    val btnColor = when {
                        isStarting -> MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
                        inProgress -> Color(0xFF34C759)
                        else -> MaterialTheme.colorScheme.primary
                    }
                    Card(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        colors = CardDefaults.cardColors(containerColor = btnColor),
                        onClick = {
                            if (!isStarting) vm.startTodayClass(onSessionClick)
                        }
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = if (inProgress) "Class In Progress" else "Start Today's Class",
                                    style = MaterialTheme.typography.titleMedium,
                                    color = Color.White
                                )
                                if (inProgress && todaySession?.startedAt != null) {
                                    val startedDate = runCatching {
                                        java.time.Instant.parse(todaySession.startedAt).let {
                                            Date(it.toEpochMilli())
                                        }
                                    }.getOrNull()
                                    if (startedDate != null) {
                                        Text(
                                            text = "Started ${timeFmt.format(startedDate)}",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = Color.White.copy(alpha = 0.85f)
                                        )
                                    }
                                }
                            }
                            if (isStarting) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    color = Color.White,
                                    strokeWidth = 2.dp
                                )
                            }
                        }
                    }
                }

                if (sessions.isEmpty()) {
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
                    items(sessions, key = { it.id }) { session ->
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

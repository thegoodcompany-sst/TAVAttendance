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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.Analytics
import com.example.tavattendance.core.AnalyticsEventType
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.data.models.*
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.ZoneOffset

class PastSessionViewModel(app: Application) : AndroidViewModel(app) {
    private val _sessions = MutableStateFlow<List<Session>>(emptyList())
    val sessions = _sessions.asStateFlow()
    private val _tutors = MutableStateFlow<List<Profile>>(emptyList())
    val tutors = _tutors.asStateFlow()
    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()
    private val _isSaving = MutableStateFlow(false)
    val isSaving = _isSaving.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private var classId = ""

    fun init(classId: String) {
        if (this.classId == classId) return
        this.classId = classId
        viewModelScope.launch {
            _isLoading.value = true
            runCatching {
                coroutineScope {
                    val sessions = async { AttendanceService.fetchSessions(classId) }
                    val tutors = async { AttendanceService.fetchTutors() }
                    sessions.await() to tutors.await()
                }
            }.onSuccess { (sessions, tutors) ->
                _sessions.value = sessions
                _tutors.value = tutors
            }.onFailure { _error.value = "Could not load the past-session form." }
            _isLoading.value = false
        }
    }

    fun clearError() { _error.value = null }

    fun create(
        date: String,
        topic: String,
        notes: String,
        subTutorId: String?,
        sessionNotesEnabled: Boolean,
        onCreated: (Session) -> Unit,
        onExisting: (Session) -> Unit
    ) {
        if (!RetrospectiveSessionRules.isPastDate(date)) {
            _error.value = "Choose a date before today."
            return
        }
        RetrospectiveSessionRules.existingSession(date, _sessions.value)?.let {
            onExisting(it)
            return
        }
        viewModelScope.launch {
            _isSaving.value = true
            runCatching {
                AttendanceService.createRetrospectiveSession(
                    classId = classId,
                    sessionDate = date,
                    topic = topic.trim().ifEmpty { null },
                    notes = if (sessionNotesEnabled) notes.trim().ifEmpty { null } else null,
                    subTutorId = subTutorId
                )
            }.onSuccess { created ->
                _sessions.value = listOf(created) + _sessions.value
                Analytics.track(
                    AnalyticsEventType.OPS,
                    "retrospective_session_created",
                    buildJsonObject { put("screen", "session_list") }
                )
                onCreated(created)
            }.onFailure {
                _error.value = "Could not create the past session: ${it.localizedMessage ?: it.javaClass.simpleName}"
            }
            _isSaving.value = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PastSessionScreen(
    classId: String,
    className: String,
    onBack: () -> Unit,
    onCreated: (Session) -> Unit,
    onExisting: (Session) -> Unit,
    vm: PastSessionViewModel = viewModel()
) {
    TrackScreen("past_session_form")
    LaunchedEffect(classId) { vm.init(classId) }
    val tutors by vm.tutors.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val isSaving by vm.isSaving.collectAsState()
    val error by vm.error.collectAsState()
    val flags by FeatureFlags.flags.collectAsState()
    val online by rememberNetworkAvailable()

    var date by remember { mutableStateOf(RetrospectiveSessionRules.today().minusDays(1).toString()) }
    var topic by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var tutorId by remember { mutableStateOf<String?>(null) }
    var showDatePicker by remember { mutableStateOf(false) }

    error?.let { message ->
        AlertDialog(
            onDismissRequest = vm::clearError,
            title = { Text("Could Not Create Session") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = vm::clearError) { Text("OK") } }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Add Past Session") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        enabled = online && !isLoading && !isSaving,
                        onClick = {
                            vm.create(
                                date, topic, notes, tutorId,
                                flags[FeatureFlags.SESSION_NOTES] == true,
                                onCreated, onExisting
                            )
                        }
                    ) { Text(if (isSaving) "Saving…" else "Create") }
                }
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                if (!online) OnlineOnlyWarning("Connect to the internet to create a past session.")
                Text(className, style = MaterialTheme.typography.titleMedium)
                OutlinedButton(onClick = { showDatePicker = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Date: $date")
                }
                OutlinedTextField(
                    value = topic,
                    onValueChange = { topic = it },
                    label = { Text("Topic (optional)") },
                    modifier = Modifier.fillMaxWidth()
                )
                if (flags[FeatureFlags.SESSION_NOTES] == true) {
                    OutlinedTextField(
                        value = notes,
                        onValueChange = { notes = it },
                        label = { Text("Notes (optional)") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                TutorSelector(tutors = tutors, selectedId = tutorId, onSelected = { tutorId = it })
            }
        }
    }

    if (showDatePicker) {
        val initialMillis = java.time.LocalDate.parse(date).atStartOfDay(ZoneOffset.UTC)
            .toInstant().toEpochMilli()
        val todayEpochDay = RetrospectiveSessionRules.today().toEpochDay()
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = initialMillis,
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                    Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().toEpochDay() < todayEpochDay
            }
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let {
                        date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()
                    }
                    showDatePicker = false
                }) { Text("Choose") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("Cancel") } }
        ) { DatePicker(state = pickerState) }
    }
}

class HistoricalSessionViewModel(app: Application) : AndroidViewModel(app) {
    private val _session = MutableStateFlow<Session?>(null)
    val session = _session.asStateFlow()
    private val _roster = MutableStateFlow<List<RosterEntry>>(emptyList())
    val roster = _roster.asStateFlow()
    private val _students = MutableStateFlow<List<Student>>(emptyList())
    val students = _students.asStateFlow()
    private val _tutors = MutableStateFlow<List<Profile>>(emptyList())
    val tutors = _tutors.asStateFlow()
    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()
    private val _isSaving = MutableStateFlow(false)
    val isSaving = _isSaving.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private var sessionId = ""

    fun init(sessionId: String, classId: String) {
        if (this.sessionId == sessionId) return
        this.sessionId = sessionId
        viewModelScope.launch {
            _isLoading.value = true
            runCatching {
                coroutineScope {
                    val sessions = async { AttendanceService.fetchSessions(classId) }
                    val roster = async { AttendanceService.fetchRetrospectiveRoster(sessionId) }
                    val students = async { AttendanceService.fetchAllStudents() }
                    val tutors = async { AttendanceService.fetchTutors() }
                    EditorLoad(
                        session = sessions.await().first { it.id == sessionId },
                        roster = roster.await(),
                        students = students.await(),
                        tutors = tutors.await()
                    )
                }
            }.onSuccess {
                _session.value = it.session
                _roster.value = it.roster
                _students.value = it.students
                _tutors.value = it.tutors
            }.onFailure {
                _error.value = "Could not load the historical editor: ${it.localizedMessage ?: it.javaClass.simpleName}"
            }
            _isLoading.value = false
        }
    }

    fun clearError() { _error.value = null }

    fun saveDetails(topic: String, notes: String, subTutorId: String?, notesEnabled: Boolean) {
        val current = _session.value ?: return
        viewModelScope.launch {
            _isSaving.value = true
            runCatching {
                AttendanceService.updateRetrospectiveSession(
                    current.id,
                    topic.trim().ifEmpty { null },
                    if (notesEnabled) notes.trim().ifEmpty { null } else null,
                    subTutorId
                )
            }.onSuccess {
                _session.value = it
                Analytics.track(
                    AnalyticsEventType.OPS,
                    "retrospective_session_updated",
                    buildJsonObject { put("screen", "historical_editor") }
                )
            }.onFailure {
                _error.value = "Could not save session details: ${it.localizedMessage ?: it.javaClass.simpleName}"
            }
            _isSaving.value = false
        }
    }

    fun mark(studentId: String, status: AttendanceStatus, isAdded: Boolean) {
        viewModelScope.launch {
            runCatching {
                AttendanceService.markRetrospectiveAttendance(sessionId, studentId, status)
                AttendanceService.fetchRetrospectiveRoster(sessionId)
            }.onSuccess {
                _roster.value = it
                Analytics.track(
                    AnalyticsEventType.OPS,
                    if (isAdded) "retrospective_student_added" else "retrospective_attendance_corrected",
                    buildJsonObject {
                        put("screen", "historical_editor")
                        put("status", status.name)
                    }
                )
            }.onFailure {
                _error.value = "Could not update historical attendance: ${it.localizedMessage ?: it.javaClass.simpleName}"
            }
        }
    }

    private data class EditorLoad(
        val session: Session,
        val roster: List<RosterEntry>,
        val students: List<Student>,
        val tutors: List<Profile>
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoricalSessionScreen(
    sessionId: String,
    classId: String,
    className: String,
    onBack: () -> Unit,
    vm: HistoricalSessionViewModel = viewModel()
) {
    TrackScreen("historical_editor")
    LaunchedEffect(sessionId, classId) { vm.init(sessionId, classId) }
    val session by vm.session.collectAsState()
    val roster by vm.roster.collectAsState()
    val students by vm.students.collectAsState()
    val tutors by vm.tutors.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val isSaving by vm.isSaving.collectAsState()
    val error by vm.error.collectAsState()
    val flags by FeatureFlags.flags.collectAsState()
    val online by rememberNetworkAvailable()

    var topic by remember(session?.id) { mutableStateOf(session?.topic.orEmpty()) }
    var notes by remember(session?.id) { mutableStateOf(session?.notes.orEmpty()) }
    var tutorId by remember(session?.id) { mutableStateOf(session?.subTutorId) }
    var showStudentPicker by remember { mutableStateOf(false) }
    var selectedStudent by remember { mutableStateOf<Student?>(null) }

    error?.let { message ->
        AlertDialog(
            onDismissRequest = vm::clearError,
            title = { Text("Historical Session") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = vm::clearError) { Text("OK") } }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Edit Session") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading || session == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (!online) item { OnlineOnlyWarning("Historical changes are online only.") }
                item { Text(className, style = MaterialTheme.typography.titleMedium) }
                item { Text("Date: ${session!!.sessionDate}") }
                item {
                    OutlinedTextField(
                        value = topic,
                        onValueChange = { topic = it },
                        label = { Text("Topic (optional)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                if (flags[FeatureFlags.SESSION_NOTES] == true) {
                    item {
                        OutlinedTextField(
                            value = notes,
                            onValueChange = { notes = it },
                            label = { Text("Notes (optional)") },
                            minLines = 3,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
                item { TutorSelector(tutors, tutorId) { tutorId = it } }
                item {
                    Button(
                        enabled = online && !isSaving,
                        onClick = {
                            vm.saveDetails(
                                topic, notes, tutorId,
                                flags[FeatureFlags.SESSION_NOTES] == true
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(if (isSaving) "Saving…" else "Save Details") }
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Attendance", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        TextButton(enabled = online, onClick = { showStudentPicker = true }) {
                            Icon(Icons.Default.Add, contentDescription = null)
                            Text("Add Student")
                        }
                    }
                }
                items(roster, key = { it.studentId }) { entry ->
                    ListItem(
                        headlineContent = { Text(entry.fullName) },
                        trailingContent = {
                            StatusSelector(entry.status, enabled = online) {
                                vm.mark(entry.studentId, it, false)
                            }
                        }
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    val rosterIds = roster.mapTo(mutableSetOf()) { it.studentId }
    val availableStudents = students.filterNot { it.id in rosterIds }
    if (showStudentPicker) {
        AlertDialog(
            onDismissRequest = { showStudentPicker = false },
            title = { Text("Add Student") },
            text = {
                if (availableStudents.isEmpty()) {
                    Text("No students to add.")
                } else {
                    LazyColumn(modifier = Modifier.heightIn(max = 420.dp)) {
                        items(availableStudents, key = { it.id }) { student ->
                            Text(
                                student.fullName,
                                modifier = Modifier.fillMaxWidth().clickable {
                                    selectedStudent = student
                                    showStudentPicker = false
                                }.padding(vertical = 12.dp)
                            )
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showStudentPicker = false }) { Text("Cancel") } }
        )
    }
    selectedStudent?.let { student ->
        AlertDialog(
            onDismissRequest = { selectedStudent = null },
            title = { Text("Mark ${student.fullName}") },
            text = {
                Column {
                    AttendanceStatus.entries.forEach { status ->
                        Text(
                            status.label,
                            modifier = Modifier.fillMaxWidth().clickable {
                                vm.mark(student.id, status, true)
                                selectedStudent = null
                            }.padding(vertical = 12.dp)
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = { selectedStudent = null }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun TutorSelector(tutors: List<Profile>, selectedId: String?, onSelected: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val label = tutors.firstOrNull { it.id == selectedId }?.fullName ?: "None"
    Box {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Text("Substitute: $label")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("None") }, onClick = { onSelected(null); expanded = false })
            tutors.forEach { tutor ->
                DropdownMenuItem(
                    text = { Text(tutor.fullName) },
                    onClick = { onSelected(tutor.id); expanded = false }
                )
            }
        }
    }
}

@Composable
private fun StatusSelector(
    status: AttendanceStatus?,
    enabled: Boolean,
    onSelected: (AttendanceStatus) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(enabled = enabled, onClick = { expanded = true }) {
            Text(status?.label ?: "Unmarked")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            AttendanceStatus.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.label) },
                    onClick = { onSelected(option); expanded = false }
                )
            }
        }
    }
}

private val AttendanceStatus.label: String
    get() = name.replaceFirstChar { it.uppercase() }

@Composable
private fun OnlineOnlyWarning(message: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Default.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
        Spacer(Modifier.width(8.dp))
        Text(message, color = MaterialTheme.colorScheme.error)
    }
}

@Composable
private fun rememberNetworkAvailable(): State<Boolean> {
    val context = LocalContext.current
    return produceState(initialValue = context.networkAvailable(), context) {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { value = true }
            override fun onLost(network: Network) { value = context.networkAvailable() }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        manager.registerNetworkCallback(request, callback)
        awaitDispose { manager.unregisterNetworkCallback(callback) }
    }
}

private fun Context.networkAvailable(): Boolean {
    val manager = getSystemService(ConnectivityManager::class.java)
    return manager.activeNetwork?.let { network ->
        manager.getNetworkCapabilities(network)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    } == true
}

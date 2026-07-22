package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.core.asUserMessage
import com.example.tavattendance.core.rememberSnackbarError
import com.example.tavattendance.core.SupabaseClient
import com.example.tavattendance.data.models.AttendanceHistoryRecord
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.ParentMessage
import com.example.tavattendance.data.models.ResultSlip
import com.example.tavattendance.data.models.ResultSlipInputValidation
import com.example.tavattendance.data.models.ResultSubject
import com.example.tavattendance.data.service.AttendanceService
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.util.*

private fun profileStateKey(
    studentId: String,
    parentMode: Boolean,
    canManageStaffResults: Boolean
): String = "$studentId|$parentMode|$canManageStaffResults"

class StudentProfileViewModel(app: Application) : AndroidViewModel(app) {
    private val _activeProfileKey = MutableStateFlow<String?>(null)
    val activeProfileKey = _activeProfileKey.asStateFlow()

    private val _history = MutableStateFlow<List<AttendanceHistoryRecord>>(emptyList())
    val history = _history.asStateFlow()

    private val _slips = MutableStateFlow<List<ResultSlip>>(emptyList())
    val slips = _slips.asStateFlow()

    private val _messages = MutableStateFlow<List<ParentMessage>>(emptyList())
    val messages = _messages.asStateFlow()

    private val _historyLoading = MutableStateFlow(true)
    val historyLoading = _historyLoading.asStateFlow()

    private val _slipsLoading = MutableStateFlow(false)
    val slipsLoading = _slipsLoading.asStateFlow()

    private val _messagesLoading = MutableStateFlow(false)
    val messagesLoading = _messagesLoading.asStateFlow()

    private val _historyError = MutableStateFlow<String?>(null)
    val historyError = _historyError.asStateFlow()

    private val _slipsError = MutableStateFlow<String?>(null)
    val slipsError = _slipsError.asStateFlow()

    private val _messagesError = MutableStateFlow<String?>(null)
    val messagesError = _messagesError.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    private val _isSubmittingResult = MutableStateFlow(false)
    val isSubmittingResult = _isSubmittingResult.asStateFlow()

    private val _isSendingMessage = MutableStateFlow(false)
    val isSendingMessage = _isSendingMessage.asStateFlow()

    private var activeStudentId: String? = null
    private var activeParentMode = false
    private var studentGeneration = 0L
    private var historyRequest = 0L
    private var slipsRequest = 0L
    private var messagesRequest = 0L
    private var historyJob: Job? = null
    private var slipsJob: Job? = null
    private var messagesJob: Job? = null

    fun clearSnackbar() { _snackbarMessage.value = null }

    private fun activateProfile(
        studentId: String,
        parentMode: Boolean,
        canManageStaffResults: Boolean
    ) {
        val key = profileStateKey(studentId, parentMode, canManageStaffResults)
        if (_activeProfileKey.value == key) return

        studentGeneration += 1
        historyRequest += 1
        slipsRequest += 1
        messagesRequest += 1
        historyJob?.cancel()
        slipsJob?.cancel()
        messagesJob?.cancel()

        // Clear the prior student's state before publishing the new identity.
        // The composable also compares activeProfileKey, so no intermediate
        // recomposition can label old data with the new student's name.
        _history.value = emptyList()
        _slips.value = emptyList()
        _messages.value = emptyList()
        _historyError.value = null
        _slipsError.value = null
        _messagesError.value = null
        _snackbarMessage.value = null
        _historyLoading.value = true
        _slipsLoading.value = false
        _messagesLoading.value = false
        _isSubmittingResult.value = false
        _isSendingMessage.value = false

        activeStudentId = studentId
        activeParentMode = parentMode
        _activeProfileKey.value = key
    }

    private fun currentGeneration(studentId: String, parentMode: Boolean): Long? =
        studentGeneration.takeIf {
            activeStudentId == studentId && activeParentMode == parentMode
        }

    private fun isCurrent(
        studentId: String,
        parentMode: Boolean,
        generation: Long
    ): Boolean = generation == studentGeneration
        && activeStudentId == studentId
        && activeParentMode == parentMode

    fun loadHistory(studentId: String, parentMode: Boolean) {
        val generation = currentGeneration(studentId, parentMode) ?: return
        val request = ++historyRequest
        historyJob?.cancel()
        _history.value = emptyList()
        _historyLoading.value = true
        _historyError.value = null
        historyJob = viewModelScope.launch {
            val since30Days = LocalDate.now().minusDays(30).toString()
            try {
                val loaded = if (parentMode) {
                    AttendanceService.fetchParentAttendanceHistory(
                        studentId = studentId, limit = 100, since = since30Days
                    )
                } else {
                    AttendanceService.fetchStudentAttendanceHistory(
                        studentId = studentId, limit = 100, since = since30Days
                    )
                }
                if (isCurrent(studentId, parentMode, generation) && request == historyRequest) {
                    _history.value = loaded
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (isCurrent(studentId, parentMode, generation) && request == historyRequest) {
                    _historyError.value = error.asUserMessage("Couldn't load attendance")
                }
            } finally {
                if (isCurrent(studentId, parentMode, generation) && request == historyRequest) {
                    _historyLoading.value = false
                }
            }
        }
    }

    fun loadSlips(studentId: String, parentMode: Boolean) {
        val generation = currentGeneration(studentId, parentMode) ?: return
        val request = ++slipsRequest
        slipsJob?.cancel()
        _slips.value = emptyList()
        _slipsLoading.value = true
        _slipsError.value = null
        slipsJob = viewModelScope.launch {
            try {
                val loaded = if (parentMode) {
                    AttendanceService.fetchResultSlips(studentId)
                } else {
                    AttendanceService.fetchStaffResultSlips(studentId)
                }
                if (isCurrent(studentId, parentMode, generation) && request == slipsRequest) {
                    _slips.value = loaded
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (isCurrent(studentId, parentMode, generation) && request == slipsRequest) {
                    _slipsError.value = error.asUserMessage("Couldn't load result slips")
                }
            } finally {
                if (isCurrent(studentId, parentMode, generation) && request == slipsRequest) {
                    _slipsLoading.value = false
                }
            }
        }
    }

    fun loadMessages(studentId: String) {
        val generation = currentGeneration(studentId, parentMode = true) ?: return
        val request = ++messagesRequest
        messagesJob?.cancel()
        _messages.value = emptyList()
        _messagesLoading.value = true
        _messagesError.value = null
        messagesJob = viewModelScope.launch {
            try {
                val loaded = AttendanceService.fetchMessages(studentId)
                if (isCurrent(studentId, parentMode = true, generation) && request == messagesRequest) {
                    _messages.value = loaded
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (isCurrent(studentId, parentMode = true, generation) && request == messagesRequest) {
                    _messagesError.value = error.asUserMessage("Couldn't load messages")
                }
            } finally {
                if (isCurrent(studentId, parentMode = true, generation) && request == messagesRequest) {
                    _messagesLoading.value = false
                }
            }
        }
    }

    fun loadAll(studentId: String, parentMode: Boolean, canManageStaffResults: Boolean) {
        activateProfile(studentId, parentMode, canManageStaffResults)
        loadHistory(studentId, parentMode)
        if (parentMode || canManageStaffResults) {
            loadSlips(studentId, parentMode)
        } else {
            slipsRequest += 1
            slipsJob?.cancel()
            _slips.value = emptyList()
            _slipsError.value = null
            _slipsLoading.value = false
        }
        if (parentMode) {
            loadMessages(studentId)
        } else {
            messagesRequest += 1
            messagesJob?.cancel()
            _messages.value = emptyList()
            _messagesError.value = null
            _messagesLoading.value = false
        }
    }

    fun submitResult(
        studentId: String,
        examName: String,
        examDate: String,
        subject: String,
        score: Double,
        maxScore: Double,
        parentMode: Boolean,
        onSuccess: () -> Unit
    ) {
        val generation = currentGeneration(studentId, parentMode) ?: return
        viewModelScope.launch {
            if (!isCurrent(studentId, parentMode, generation)) return@launch
            val failure = ResultSlipInputValidation.validate(examName, score, maxScore)
            if (failure != null) {
                if (isCurrent(studentId, parentMode, generation)) {
                    _snackbarMessage.value = failure.message
                }
                return@launch
            }
            _isSubmittingResult.value = true
            runCatching {
                if (parentMode) {
                    AttendanceService.submitResultSlip(
                        studentId = studentId,
                        examName = examName.trim(),
                        examDate = examDate,
                        subject = subject,
                        score = score,
                        maxScore = maxScore
                    )
                } else {
                    val userId = SupabaseClient.client.auth.currentUserOrNull()?.id
                        ?: error("No authenticated staff user")
                    AttendanceService.submitStaffResultSlip(
                        studentId = studentId,
                        examName = examName.trim(),
                        examDate = examDate,
                        subject = subject,
                        score = score,
                        maxScore = maxScore,
                        uploadedBy = userId
                    )
                }
            }.onSuccess {
                if (isCurrent(studentId, parentMode, generation)) {
                    loadSlips(studentId, parentMode)
                    onSuccess()
                }
            }.onFailure { error ->
                if (isCurrent(studentId, parentMode, generation)) {
                    _snackbarMessage.value = error.asUserMessage("Couldn't submit result")
                }
            }
            if (isCurrent(studentId, parentMode, generation)) {
                _isSubmittingResult.value = false
            }
        }
    }

    fun sendMessage(
        studentId: String,
        subject: String?,
        body: String,
        onSuccess: () -> Unit
    ) {
        val generation = currentGeneration(studentId, parentMode = true) ?: return
        viewModelScope.launch {
            if (!isCurrent(studentId, parentMode = true, generation)) return@launch
            val trimmed = body.trim()
            if (trimmed.isEmpty()) {
                if (isCurrent(studentId, parentMode = true, generation)) {
                    _snackbarMessage.value = "Message cannot be empty."
                }
                return@launch
            }
            _isSendingMessage.value = true
            runCatching {
                AttendanceService.sendParentMessage(
                    studentId = studentId,
                    subject = subject?.trim()?.ifEmpty { null },
                    body = trimmed
                )
            }.onSuccess {
                if (isCurrent(studentId, parentMode = true, generation)) {
                    loadMessages(studentId)
                    onSuccess()
                }
            }.onFailure { error ->
                if (isCurrent(studentId, parentMode = true, generation)) {
                    _snackbarMessage.value = error.asUserMessage("Couldn't send message")
                }
            }
            if (isCurrent(studentId, parentMode = true, generation)) {
                _isSendingMessage.value = false
            }
        }
    }
}

private enum class ParentProfileTab { Attendance, Results, Messages }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentProfileSheet(
    studentId: String,
    fullName: String,
    onDismiss: () -> Unit,
    isParentMode: Boolean = false,
    canManageStaffResults: Boolean = false,
    vm: StudentProfileViewModel = viewModel()
) {
    TrackScreen("student_profile")
    LaunchedEffect(studentId, isParentMode, canManageStaffResults) {
        vm.loadAll(studentId, isParentMode, canManageStaffResults)
    }

    val activeProfileKey by vm.activeProfileKey.collectAsState()
    val loadedHistory by vm.history.collectAsState()
    val loadedSlips by vm.slips.collectAsState()
    val loadedMessages by vm.messages.collectAsState()
    val loadedHistoryLoading by vm.historyLoading.collectAsState()
    val loadedSlipsLoading by vm.slipsLoading.collectAsState()
    val loadedMessagesLoading by vm.messagesLoading.collectAsState()
    val loadedHistoryError by vm.historyError.collectAsState()
    val loadedSlipsError by vm.slipsError.collectAsState()
    val loadedMessagesError by vm.messagesError.collectAsState()
    val loadedSnackbarMessage by vm.snackbarMessage.collectAsState()
    val loadedIsSubmittingResult by vm.isSubmittingResult.collectAsState()
    val loadedIsSendingMessage by vm.isSendingMessage.collectAsState()

    val stateIsCurrent = activeProfileKey == profileStateKey(
        studentId,
        isParentMode,
        canManageStaffResults
    )
    val history = if (stateIsCurrent) loadedHistory else emptyList()
    val slips = if (stateIsCurrent) loadedSlips else emptyList()
    val messages = if (stateIsCurrent) loadedMessages else emptyList()
    val historyLoading = !stateIsCurrent || loadedHistoryLoading
    val slipsLoading = !stateIsCurrent || loadedSlipsLoading
    val messagesLoading = !stateIsCurrent || loadedMessagesLoading
    val historyError = loadedHistoryError.takeIf { stateIsCurrent }
    val slipsError = loadedSlipsError.takeIf { stateIsCurrent }
    val messagesError = loadedMessagesError.takeIf { stateIsCurrent }
    val snackbarMessage = loadedSnackbarMessage.takeIf { stateIsCurrent }
    val isSubmittingResult = stateIsCurrent && loadedIsSubmittingResult
    val isSendingMessage = stateIsCurrent && loadedIsSendingMessage

    val snackbarHost = rememberSnackbarError(snackbarMessage) { vm.clearSnackbar() }
    var selectedTab by remember(studentId) { mutableStateOf(ParentProfileTab.Attendance) }
    var showAddResult by remember(studentId) { mutableStateOf(false) }

    val presentCount = history.count { it.status == AttendanceStatus.present }
    val lateCount = history.count { it.status == AttendanceStatus.late }
    val absentCount = history.count { it.status == AttendanceStatus.absent }
    val excusedCount = history.count { it.status == AttendanceStatus.excused }
    val attendanceRate = if (history.isNotEmpty())
        (presentCount + lateCount + excusedCount).toFloat() / history.size else 0f

    val isoFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val prettyFmt = SimpleDateFormat("MMM d, yyyy", Locale.US)
    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    fun formatDate(iso: String) = runCatching { prettyFmt.format(isoFmt.parse(iso)!!) }.getOrDefault(iso)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Scaffold(
            snackbarHost = { SnackbarHost(snackbarHost) },
            containerColor = Color.Transparent
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(padding)
                    .padding(horizontal = 16.dp)
            ) {
                Text(fullName, style = MaterialTheme.typography.headlineSmall)
                Spacer(Modifier.height(12.dp))

                if (isParentMode) {
                    TabRow(selectedTabIndex = selectedTab.ordinal) {
                        ParentProfileTab.entries.forEach { tab ->
                            Tab(
                                selected = selectedTab == tab,
                                onClick = {
                                    selectedTab = tab
                                    if (tab == ParentProfileTab.Messages) vm.loadMessages(studentId)
                                    if (tab == ParentProfileTab.Results) vm.loadSlips(studentId, true)
                                },
                                text = { Text(tab.name) }
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                when {
                    !isParentMode || selectedTab == ParentProfileTab.Attendance -> {
                        AttendanceTabContent(
                            modifier = Modifier.weight(1f, fill = false),
                            history = history,
                            isLoading = historyLoading,
                            error = historyError,
                            presentCount = presentCount,
                            lateCount = lateCount,
                            absentCount = absentCount,
                            excusedCount = excusedCount,
                            attendanceRate = attendanceRate,
                            formatDate = ::formatDate,
                            timeFmt = timeFmt,
                            onRetry = { vm.loadHistory(studentId, isParentMode) },
                            includeStaffResults = !isParentMode && canManageStaffResults,
                            slips = slips,
                            slipsLoading = slipsLoading,
                            slipsError = slipsError,
                            onRetrySlips = { vm.loadSlips(studentId, false) },
                            onAddResult = { showAddResult = true },
                        )
                    }
                    selectedTab == ParentProfileTab.Results -> {
                        ResultsTabContent(
                            slips = slips,
                            isLoading = slipsLoading,
                            error = slipsError,
                            formatDate = ::formatDate,
                            onRetry = { vm.loadSlips(studentId, true) },
                            onAddResult = { showAddResult = true },
                            isParentMode = true
                        )
                    }
                    selectedTab == ParentProfileTab.Messages -> {
                        MessagesTabContent(
                            messages = messages,
                            isLoading = messagesLoading,
                            error = messagesError,
                            isSending = isSendingMessage,
                            onRetry = { vm.loadMessages(studentId) },
                            onSend = { subject, body, clear ->
                                vm.sendMessage(studentId, subject, body) { clear() }
                            }
                        )
                    }
                }
                Spacer(Modifier.height(32.dp))
            }
        }
    }

    if (showAddResult && (isParentMode || canManageStaffResults)) {
        AddResultDialog(
            isSubmitting = isSubmittingResult,
            onDismiss = { showAddResult = false },
            onSubmit = { name, date, subject, score, maxScore ->
                vm.submitResult(studentId, name, date, subject, score, maxScore, isParentMode) {
                    showAddResult = false
                }
            }
        )
    }
}

@Composable
private fun AttendanceTabContent(
    modifier: Modifier = Modifier,
    history: List<AttendanceHistoryRecord>,
    isLoading: Boolean,
    error: String?,
    presentCount: Int,
    lateCount: Int,
    absentCount: Int,
    excusedCount: Int,
    attendanceRate: Float,
    formatDate: (String) -> String,
    timeFmt: SimpleDateFormat,
    onRetry: () -> Unit,
    includeStaffResults: Boolean,
    slips: List<ResultSlip>,
    slipsLoading: Boolean,
    slipsError: String?,
    onRetrySlips: () -> Unit,
    onAddResult: () -> Unit,
) {
    LazyColumn(modifier = modifier.fillMaxWidth()) {
        when {
            isLoading -> item {
                Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            error != null && history.isEmpty() -> item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(error, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = onRetry) { Text("Retry") }
                }
            }
            history.isEmpty() -> item {
                Text(
                    "No records in the last 30 days.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
            }
            else -> {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Row(modifier = Modifier.fillMaxWidth()) {
                                StatPill(presentCount, "Present", Color(0xFF34C759))
                                StatPill(lateCount, "Late", Color(0xFFFF9500))
                                StatPill(absentCount, "Absent", Color(0xFFFF3B30))
                                StatPill(excusedCount, "Excused", Color(0xFF8E8E93))
                            }
                            Spacer(Modifier.height(12.dp))
                            Row(verticalAlignment = Alignment.Bottom) {
                                val rateColor = when {
                                    attendanceRate >= 0.9f -> Color(0xFF34C759)
                                    attendanceRate >= 0.75f -> Color(0xFFFF9500)
                                    else -> Color(0xFFFF3B30)
                                }
                                Text(
                                    "${(attendanceRate * 100).toInt()}%",
                                    style = MaterialTheme.typography.displaySmall,
                                    color = rateColor
                                )
                                Spacer(Modifier.width(4.dp))
                                Text(
                                    "attendance",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(bottom = 6.dp)
                                )
                                Spacer(Modifier.weight(1f))
                                Text(
                                    "${history.size} sessions",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(bottom = 6.dp)
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth().height(8.dp)) {
                                val total = history.size.toFloat()
                                if (total > 0) {
                                    if (presentCount > 0) Surface(modifier = Modifier.weight(presentCount / total), color = Color(0xFF34C759)) {}
                                    if (lateCount > 0) Surface(modifier = Modifier.weight(lateCount / total), color = Color(0xFFFF9500)) {}
                                    if (absentCount > 0) Surface(modifier = Modifier.weight(absentCount / total), color = Color(0xFFFF3B30)) {}
                                    if (excusedCount > 0) Surface(modifier = Modifier.weight(excusedCount / total), color = Color(0xFF8E8E93)) {}
                                }
                            }
                        }
                    }
                }

                item {
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "Sessions (last 30 days)",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(8.dp))
                }

                items(history, key = { "attendance-${it.id}" }) { record ->
                    val color = statusColor(record.status)
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = color,
                            modifier = Modifier.size(10.dp)
                        ) {}
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(record.session.cls.name, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                formatDate(record.session.sessionDate),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                record.status.name.replaceFirstChar { it.uppercase() },
                                style = MaterialTheme.typography.bodyMedium,
                                color = color
                            )
                            record.markedAt?.let { timestamp ->
                                runCatching { Date(Instant.parse(timestamp).toEpochMilli()) }
                                    .getOrNull()
                                    ?.let { markedDate ->
                                        Text(
                                            timeFmt.format(markedDate),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                            }
                        }
                    }
                    HorizontalDivider()
                }
            }
        }

        if (includeStaffResults) {
            item {
                Spacer(Modifier.height(16.dp))
                Text("Result Slips", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(8.dp))
            }
            when {
                slipsLoading -> item {
                    Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                slipsError != null && slips.isEmpty() -> item {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(slipsError, color = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = onRetrySlips) { Text("Retry") }
                    }
                }
                else -> {
                    if (slips.isEmpty()) {
                        item {
                            Text(
                                "No result slips yet.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(slips, key = { "slip-${it.id}" }) { slip ->
                            ResultSlipRow(slip, formatDate, showAck = false)
                            HorizontalDivider()
                        }
                    }
                    item {
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = onAddResult, modifier = Modifier.fillMaxWidth()) {
                            Text("Add Result Slip")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultsTabContent(
    slips: List<ResultSlip>,
    isLoading: Boolean,
    error: String?,
    formatDate: (String) -> String,
    onRetry: () -> Unit,
    onAddResult: () -> Unit,
    isParentMode: Boolean
) {
    when {
        isLoading -> Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        error != null && slips.isEmpty() -> Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(error, color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(8.dp))
            Button(onClick = onRetry) { Text("Retry") }
        }
        else -> {
            LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
                if (slips.isEmpty()) {
                    item {
                        Text(
                            "No result slips yet.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    items(slips, key = { it.id }) { slip ->
                        ResultSlipRow(slip, formatDate, showAck = isParentMode)
                        HorizontalDivider()
                    }
                }
                item {
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = onAddResult, modifier = Modifier.fillMaxWidth()) {
                        Text("Add Result Slip")
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultSlipRow(
    slip: ResultSlip,
    formatDate: (String) -> String,
    showAck: Boolean
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(slip.subject ?: "—", style = MaterialTheme.typography.bodyMedium)
            slip.examName?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            slip.examDate?.let {
                Text(formatDate(it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            slip.fractionDisplay?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium)
            }
            if (showAck) {
                Text(
                    if (slip.isAcknowledged) "Acknowledged" else "Pending review",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (slip.isAcknowledged) Color(0xFF34C759) else Color(0xFFFF9500)
                )
            }
        }
    }
}

@Composable
private fun MessagesTabContent(
    messages: List<ParentMessage>,
    isLoading: Boolean,
    error: String?,
    isSending: Boolean,
    onRetry: () -> Unit,
    onSend: (subject: String?, body: String, clear: () -> Unit) -> Unit
) {
    var subject by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
    }

    Column(modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp)) {
        Box(modifier = Modifier.weight(1f, fill = false).fillMaxWidth().heightIn(min = 120.dp, max = 320.dp)) {
            when {
                isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                error != null && messages.isEmpty() -> Column(
                    modifier = Modifier.fillMaxSize().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(error, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = onRetry) { Text("Retry") }
                }
                messages.isEmpty() -> Text(
                    "No messages yet. Send a message to TAVA about this child.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(8.dp)
                )
                else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                    items(messages, key = { it.id }) { msg ->
                        val fromParent = msg.isFromParent
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            horizontalArrangement = if (fromParent) Arrangement.End else Arrangement.Start
                        ) {
                            Column(
                                modifier = Modifier
                                    .widthIn(max = 280.dp)
                                    .background(
                                        if (fromParent) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.surfaceVariant,
                                        RoundedCornerShape(14.dp)
                                    )
                                    .padding(10.dp)
                            ) {
                                msg.subject?.takeIf { it.isNotBlank() }?.let {
                                    Text(
                                        it,
                                        style = MaterialTheme.typography.labelMedium,
                                        color = if (fromParent) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                        else MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    msg.body,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = if (fromParent) MaterialTheme.colorScheme.onPrimary
                                    else MaterialTheme.colorScheme.onSurface
                                )
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = subject,
            onValueChange = { subject = it },
            label = { Text("Subject (optional)") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = body,
                onValueChange = { body = it },
                label = { Text("Message") },
                modifier = Modifier.weight(1f),
                minLines = 1,
                maxLines = 4
            )
            Spacer(Modifier.width(8.dp))
            Button(
                onClick = {
                    onSend(subject, body) {
                        subject = ""
                        body = ""
                    }
                },
                enabled = !isSending && body.isNotBlank()
            ) {
                if (isSending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else Text("Send")
            }
        }
    }
}

@Composable
private fun AddResultDialog(
    isSubmitting: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (examName: String, examDate: String, subject: String, score: Double, maxScore: Double) -> Unit
) {
    var subject by remember { mutableStateOf(ResultSubject.MATH) }
    var examName by remember { mutableStateOf("") }
    var examDate by remember { mutableStateOf(LocalDate.now().toString()) }
    var scoreText by remember { mutableStateOf("") }
    var maxScoreText by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        title = { Text("Add Result Slip") },
        text = {
            Column {
                Text("Subject", style = MaterialTheme.typography.labelMedium)
                Row {
                    ResultSubject.entries.forEach { s ->
                        FilterChip(
                            selected = subject == s,
                            onClick = { subject = s },
                            label = { Text(s.raw) },
                            modifier = Modifier.padding(end = 8.dp)
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = examName,
                    onValueChange = { examName = it },
                    label = { Text("Exam name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = examDate,
                    onValueChange = { examDate = it },
                    label = { Text("Exam date (yyyy-MM-dd)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                Row {
                    OutlinedTextField(
                        value = scoreText,
                        onValueChange = { scoreText = it },
                        label = { Text("Score") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(
                        value = maxScoreText,
                        onValueChange = { maxScoreText = it },
                        label = { Text("Max") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                }
                localError?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !isSubmitting,
                onClick = {
                    val score = scoreText.toDoubleOrNull()
                    val maxScore = maxScoreText.toDoubleOrNull()
                    val failure = ResultSlipInputValidation.validate(examName, score, maxScore)
                    if (failure != null) {
                        localError = failure.message
                        return@TextButton
                    }
                    localError = null
                    onSubmit(examName.trim(), examDate.trim(), subject.raw, score!!, maxScore!!)
                }
            ) {
                if (isSubmitting) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSubmitting) { Text("Cancel") }
        }
    )
}

@Composable
private fun RowScope.StatPill(value: Int, label: String, color: Color) {
    Column(
        modifier = Modifier.weight(1f),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("$value", style = MaterialTheme.typography.titleLarge, color = color)
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

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

    fun formatDate(iso: String) = runCatching {
        prettyFmt.format(requireNotNull(isoFmt.parse(iso)))
    }.getOrDefault(iso)

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

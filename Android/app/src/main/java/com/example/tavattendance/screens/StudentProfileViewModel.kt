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
import com.example.tavattendance.core.PdpaText
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

internal enum class ParentProfileTab { Attendance, Results, Messages }

internal fun profileStateKey(
    studentId: String,
    parentMode: Boolean,
    canManageStaffResults: Boolean
): String = "$studentId|$parentMode|$canManageStaffResults"

/** Parent mode shows Attendance / Results / Messages; staff see attendance only (plus optional staff results). */
internal fun availableStudentProfileTabs(parentMode: Boolean): List<ParentProfileTab> =
    if (parentMode) ParentProfileTab.entries.toList() else listOf(ParentProfileTab.Attendance)

/** Whether changing students (or mode) should clear student-specific UI state. */
internal fun shouldResetStudentProfileState(previousKey: String?, nextKey: String): Boolean =
    previousKey != null && previousKey != nextKey

/** Failed loads keep a non-null error so the UI can offer Retry. */
internal fun retryableLoadError(message: String?): Boolean = !message.isNullOrBlank()

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
            if (PdpaText.containsNric(subject) || PdpaText.containsNric(trimmed)) {
                if (isCurrent(studentId, parentMode = true, generation)) {
                    _snackbarMessage.value = PdpaText.NRIC_WARNING
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


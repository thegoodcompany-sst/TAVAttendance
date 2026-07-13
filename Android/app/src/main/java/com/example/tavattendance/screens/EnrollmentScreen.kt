package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.ErrorRetry
import com.example.tavattendance.core.asUserMessage
import com.example.tavattendance.core.rememberSnackbarError
import com.example.tavattendance.data.models.Enrollment
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class EnrollmentViewModel(app: Application) : AndroidViewModel(app) {
    private val _allStudents = MutableStateFlow<List<Student>>(emptyList())
    val allStudents = _allStudents.asStateFlow()

    private val _enrolledIds = MutableStateFlow<Set<String>>(emptySet())
    val enrolledIds = _enrolledIds.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    fun clearSnackbar() { _snackbarMessage.value = null }

    private var classId: String = ""

    fun init(classId: String) {
        this.classId = classId
        load()
    }

    fun load() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            runCatching {
                val students = AttendanceService.fetchAllStudents()
                val enrollments = AttendanceService.fetchEnrollments(classId)
                students to enrollments.map { it.studentId }.toSet()
            }.onSuccess { (students, ids) ->
                _allStudents.value = students
                _enrolledIds.value = ids
            }.onFailure { _loadError.value = it.asUserMessage("Failed to load students") }
            _isLoading.value = false
        }
    }

    fun toggleEnrollment(studentId: String, currentlyEnrolled: Boolean) {
        viewModelScope.launch {
            if (currentlyEnrolled) {
                runCatching { AttendanceService.unenrollStudent(studentId, classId) }
                    .onSuccess { _enrolledIds.value = _enrolledIds.value - studentId }
                    .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't unenroll student") }
            } else {
                runCatching { AttendanceService.enrollStudent(studentId, classId) }
                    .onSuccess { _enrolledIds.value = _enrolledIds.value + studentId }
                    .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't enroll student") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnrollmentScreen(
    classId: String,
    className: String,
    onBack: () -> Unit,
    vm: EnrollmentViewModel = viewModel()
) {
    LaunchedEffect(classId) { vm.init(classId) }

    val allStudents by vm.allStudents.collectAsState()
    val enrolledIds by vm.enrolledIds.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val loadError by vm.loadError.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()

    val snackbarHost = rememberSnackbarError(snackbarMessage) { vm.clearSnackbar() }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            TopAppBar(
                title = { Text("Students — $className") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (loadError != null) {
            ErrorRetry(loadError!!, onRetry = { vm.load() }, modifier = Modifier.padding(padding))
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(allStudents, key = { it.id }) { student ->
                    val enrolled = student.id in enrolledIds
                    ListItem(
                        headlineContent = { Text(student.fullName) },
                        supportingContent = {
                            student.school?.let { Text(it) }
                        },
                        trailingContent = {
                            Switch(
                                checked = enrolled,
                                onCheckedChange = { vm.toggleEnrollment(student.id, enrolled) }
                            )
                        }
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.ErrorRetry
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.core.asUserMessage
import com.example.tavattendance.core.rememberSnackbarError
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.models.StudentInsert
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class StudentManagementViewModel(app: Application) : AndroidViewModel(app) {
    private val _students = MutableStateFlow<List<Student>>(emptyList())
    val students = _students.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    fun clearSnackbar() { _snackbarMessage.value = null }

    init { loadStudents() }

    fun loadStudents() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            runCatching { AttendanceService.fetchAllStudents() }
                .onSuccess { _students.value = it }
                .onFailure { _loadError.value = it.asUserMessage("Failed to load students") }
            _isLoading.value = false
        }
    }

    fun addStudent(student: StudentInsert, consentAttested: Boolean) {
        if (!consentAttested) {
            _snackbarMessage.value = "Confirm parent/guardian consent before adding a student."
            return
        }
        viewModelScope.launch {
            runCatching {
                AttendanceService.createStudentWithConsent(
                    student, sourceNote = "Admin attestation on create")
            }.onSuccess { loadStudents() }
                .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't add student") }
        }
    }

    // consentAttested is only meaningful when creating; on edit the existing consent stands.
    fun editStudent(id: String, student: StudentInsert) {
        viewModelScope.launch {
            runCatching { AttendanceService.updateStudent(id, student) }
                .onSuccess { loadStudents() }
                .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't save student") }
        }
    }

    fun deactivateStudent(id: String) {
        viewModelScope.launch {
            runCatching { AttendanceService.deactivateStudent(id) }
                .onSuccess { loadStudents() }
                .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't deactivate student") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentManagementScreen(vm: StudentManagementViewModel = viewModel()) {
    TrackScreen("student_management")
    val students by vm.students.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val loadError by vm.loadError.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingStudent by remember { mutableStateOf<Student?>(null) }
    var profileStudent by remember { mutableStateOf<Student?>(null) }

    val snackbarHost = rememberSnackbarError(snackbarMessage) { vm.clearSnackbar() }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            TopAppBar(
                title = { Text("Students") },
                actions = {
                    IconButton(onClick = { showAddDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = "Add student")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                loadError != null -> ErrorRetry(loadError!!, onRetry = { vm.loadStudents() })
                students.isEmpty() -> Text(
                    "No active students.",
                    modifier = Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(students, key = { it.id }) { student ->
                        ListItem(
                            headlineContent = { Text(student.fullName) },
                            supportingContent = {
                                val detail = listOfNotNull(student.school, student.yearOfStudy).joinToString(" · ")
                                if (detail.isNotBlank()) Text(detail)
                            },
                            trailingContent = {
                                Row {
                                    IconButton(onClick = { editingStudent = student }) {
                                        Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(20.dp))
                                    }
                                    var showConfirm by remember { mutableStateOf(false) }
                                    IconButton(onClick = { showConfirm = true }) {
                                        Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(20.dp))
                                    }
                                    if (showConfirm) {
                                        AlertDialog(
                                            onDismissRequest = { showConfirm = false },
                                            title = { Text("Deactivate Student") },
                                            text = { Text("Deactivate \"${student.fullName}\"?") },
                                            confirmButton = {
                                                TextButton(onClick = { vm.deactivateStudent(student.id); showConfirm = false }) {
                                                    Text("Deactivate", color = MaterialTheme.colorScheme.error)
                                                }
                                            },
                                            dismissButton = {
                                                TextButton(onClick = { showConfirm = false }) { Text("Cancel") }
                                            }
                                        )
                                    }
                                }
                            },
                            modifier = Modifier.clickable { profileStudent = student }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        StudentFormDialog(
            title = "New Student",
            onDismiss = { showAddDialog = false },
            onSave = { student, consent -> vm.addStudent(student, consent); showAddDialog = false }
        )
    }

    editingStudent?.let { s ->
        StudentFormDialog(
            title = "Edit Student",
            initial = s,
            onDismiss = { editingStudent = null },
            onSave = { student, _ -> vm.editStudent(s.id, student); editingStudent = null }
        )
    }

    profileStudent?.let { s ->
        StudentProfileSheet(
            studentId = s.id,
            fullName = s.fullName,
            onDismiss = { profileStudent = null },
            canManageStaffResults = true
        )
    }
}

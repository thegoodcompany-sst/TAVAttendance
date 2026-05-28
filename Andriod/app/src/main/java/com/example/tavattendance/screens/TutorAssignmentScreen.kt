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
import com.example.tavattendance.data.models.Profile
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class TutorAssignmentViewModel(app: Application) : AndroidViewModel(app) {
    private val _tutors = MutableStateFlow<List<Profile>>(emptyList())
    val tutors = _tutors.asStateFlow()

    private val _assignedIds = MutableStateFlow<Set<String>>(emptySet())
    val assignedIds = _assignedIds.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private var classId: String = ""

    fun init(classId: String) {
        this.classId = classId
        load()
    }

    private fun load() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching {
                val tutors = AttendanceService.fetchTutors()
                val assignments = AttendanceService.fetchTutorAssignments(classId)
                _tutors.value = tutors
                _assignedIds.value = assignments.map { it.tutorId }.toSet()
            }
            _isLoading.value = false
        }
    }

    fun toggleAssignment(tutorId: String, currentlyAssigned: Boolean) {
        viewModelScope.launch {
            if (currentlyAssigned) {
                runCatching { AttendanceService.unassignTutor(tutorId, classId) }
                    .onSuccess { _assignedIds.value = _assignedIds.value - tutorId }
            } else {
                runCatching { AttendanceService.assignTutor(tutorId, classId) }
                    .onSuccess { _assignedIds.value = _assignedIds.value + tutorId }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TutorAssignmentScreen(
    classId: String,
    className: String,
    onBack: () -> Unit,
    vm: TutorAssignmentViewModel = viewModel()
) {
    LaunchedEffect(classId) { vm.init(classId) }

    val tutors by vm.tutors.collectAsState()
    val assignedIds by vm.assignedIds.collectAsState()
    val isLoading by vm.isLoading.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Tutors — $className") },
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
        } else if (tutors.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("No tutors found.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(tutors, key = { it.id }) { tutor ->
                    val assigned = tutor.id in assignedIds
                    ListItem(
                        headlineContent = { Text(tutor.fullName) },
                        supportingContent = { Text(tutor.role) },
                        trailingContent = {
                            Switch(
                                checked = assigned,
                                onCheckedChange = { vm.toggleAssignment(tutor.id, assigned) }
                            )
                        }
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

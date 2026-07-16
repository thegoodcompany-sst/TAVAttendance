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
import com.example.tavattendance.auth.AuthViewModel
import com.example.tavattendance.auth.BiometricToggleAction
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.core.ErrorRetry
import com.example.tavattendance.core.asUserMessage
import com.example.tavattendance.core.rememberSnackbarError
import com.example.tavattendance.data.models.ClassInsert
import com.example.tavattendance.data.models.TAVClass
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ClassListViewModel(app: Application) : AndroidViewModel(app) {
    private val _classes = MutableStateFlow<List<TAVClass>>(emptyList())
    val classes = _classes.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    fun clearSnackbar() { _snackbarMessage.value = null }

    init { loadClasses() }

    fun loadClasses() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            runCatching { AttendanceService.fetchMyClasses() }
                .onSuccess { _classes.value = it }
                .onFailure { _loadError.value = it.asUserMessage("Failed to load classes") }
            _isLoading.value = false
        }
    }

    fun addClass(cls: ClassInsert) {
        viewModelScope.launch {
            runCatching { AttendanceService.createClass(cls) }
                .onSuccess { loadClasses() }
                .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't create class") }
        }
    }

    fun editClass(id: String, cls: ClassInsert) {
        viewModelScope.launch {
            runCatching { AttendanceService.updateClass(id, cls) }
                .onSuccess { loadClasses() }
                .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't save class") }
        }
    }

    fun deleteClass(id: String) {
        viewModelScope.launch {
            runCatching { AttendanceService.deleteClass(id) }
                .onSuccess { loadClasses() }
                .onFailure { _snackbarMessage.value = it.asUserMessage("Couldn't deactivate class") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassListScreen(
    authViewModel: AuthViewModel,
    isAdmin: Boolean,
    onClassClick: (TAVClass) -> Unit,
    onSignOut: () -> Unit,
    vm: ClassListViewModel = viewModel()
) {
    TrackScreen("class_list")
    val classes by vm.classes.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val loadError by vm.loadError.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingClass by remember { mutableStateOf<TAVClass?>(null) }

    val snackbarHost = rememberSnackbarError(snackbarMessage) { vm.clearSnackbar() }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            TopAppBar(
                title = { Text("Classes") },
                actions = {
                    if (isAdmin) {
                        IconButton(onClick = { showAddDialog = true }) {
                            Icon(Icons.Default.Add, contentDescription = "Add class")
                        }
                    }
                    BiometricToggleAction()
                    TextButton(onClick = onSignOut) { Text("Sign Out") }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                loadError != null -> ErrorRetry(loadError!!, onRetry = { vm.loadClasses() })
                classes.isEmpty() -> Text(
                    text = "No active classes.",
                    modifier = Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(classes, key = { it.id }) { cls ->
                        ListItem(
                            headlineContent = { Text(cls.name) },
                            supportingContent = {
                                val detail = listOfNotNull(
                                    cls.subject,
                                    cls.level,
                                    cls.scheduleDay?.let { d ->
                                        cls.scheduleTime?.let { t -> "$d ${t.take(5)}" } ?: d
                                    }
                                ).joinToString(" · ")
                                if (detail.isNotBlank()) Text(detail)
                            },
                            trailingContent = {
                                if (isAdmin) {
                                    Row {
                                        IconButton(onClick = { editingClass = cls }) {
                                            Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(20.dp))
                                        }
                                        var showConfirm by remember { mutableStateOf(false) }
                                        IconButton(onClick = { showConfirm = true }) {
                                            Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(20.dp))
                                        }
                                        if (showConfirm) {
                                            AlertDialog(
                                                onDismissRequest = { showConfirm = false },
                                                title = { Text("Deactivate Class") },
                                                text = { Text("Deactivate \"${cls.name}\"?") },
                                                confirmButton = {
                                                    TextButton(onClick = { vm.deleteClass(cls.id); showConfirm = false }) {
                                                        Text("Deactivate", color = MaterialTheme.colorScheme.error)
                                                    }
                                                },
                                                dismissButton = {
                                                    TextButton(onClick = { showConfirm = false }) { Text("Cancel") }
                                                }
                                            )
                                        }
                                    }
                                }
                            },
                            modifier = Modifier.clickable { onClassClick(cls) }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        ClassFormDialog(
            title = "New Class",
            onDismiss = { showAddDialog = false },
            onSave = { insert -> vm.addClass(insert); showAddDialog = false }
        )
    }

    editingClass?.let { cls ->
        ClassFormDialog(
            title = "Edit Class",
            initial = cls,
            onDismiss = { editingClass = null },
            onSave = { insert -> vm.editClass(cls.id, insert); editingClass = null }
        )
    }
}

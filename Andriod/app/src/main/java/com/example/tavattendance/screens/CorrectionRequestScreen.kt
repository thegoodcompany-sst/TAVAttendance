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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.CorrectionRequest
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class CorrectionRequestViewModel(app: Application) : AndroidViewModel(app) {
    private val _requests = MutableStateFlow<List<CorrectionRequest>>(emptyList())
    val requests = _requests.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            runCatching { AttendanceService.fetchPendingCorrectionRequests() }
                .onSuccess { _requests.value = it }
                .onFailure { _error.value = it.message ?: "Failed to load requests" }
            _isLoading.value = false
        }
    }

    fun apply(request: CorrectionRequest) {
        viewModelScope.launch {
            _error.value = null
            runCatching { AttendanceService.applyCorrectionRequest(request) }
                .onSuccess { load() }
                .onFailure { _error.value = it.message ?: "Failed to apply correction" }
        }
    }

    fun reject(request: CorrectionRequest, note: String?) {
        viewModelScope.launch {
            _error.value = null
            runCatching { AttendanceService.rejectCorrectionRequest(request, note) }
                .onSuccess { load() }
                .onFailure { _error.value = it.message ?: "Failed to reject correction" }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CorrectionRequestScreen(
    onBack: () -> Unit,
    vm: CorrectionRequestViewModel = viewModel()
) {
    val requests by vm.requests.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val error by vm.error.collectAsState()
    var rejecting by remember { mutableStateOf<CorrectionRequest?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Correction Requests") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                isLoading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                error != null -> Column(
                    Modifier.align(Alignment.Center).padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { vm.load() }) { Text("Retry") }
                }
                requests.isEmpty() -> Text(
                    "No pending correction requests.",
                    Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                else -> LazyColumn(Modifier.fillMaxSize().padding(12.dp)) {
                    items(requests, key = { it.id }) { req ->
                        ElevatedCard(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                            Column(Modifier.padding(16.dp)) {
                                Text(req.fieldName, fontWeight = FontWeight.SemiBold)
                                Spacer(Modifier.height(4.dp))
                                Text("Current: ${req.currentValue ?: "—"}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text("Requested: ${req.requestedValue ?: "—"}",
                                    style = MaterialTheme.typography.bodyMedium)
                                Spacer(Modifier.height(12.dp))
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { vm.apply(req) }) { Text("Apply") }
                                    OutlinedButton(onClick = { rejecting = req }) { Text("Reject") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    rejecting?.let { req ->
        var note by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { rejecting = null },
            title = { Text("Reject request") },
            text = {
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("Reason (optional)") },
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    vm.reject(req, note.trim().ifBlank { null })
                    rejecting = null
                }) { Text("Reject", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { rejecting = null }) { Text("Cancel") } }
        )
    }
}

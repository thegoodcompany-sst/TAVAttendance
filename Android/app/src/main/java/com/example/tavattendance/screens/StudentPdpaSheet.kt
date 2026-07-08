package com.example.tavattendance.screens

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.ConsentRecord
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class StudentPdpaViewModel(app: Application) : AndroidViewModel(app) {
    private val _consent = MutableStateFlow<List<ConsentRecord>>(emptyList())
    val consent = _consent.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy = _busy.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message = _message.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    fun load(studentId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            runCatching { AttendanceService.fetchCurrentConsent(studentId) }
                .onSuccess { _consent.value = it }
                .onFailure { _error.value = it.message ?: "Failed to load consent" }
            _isLoading.value = false
        }
    }

    fun withdrawConsent(studentId: String) {
        runOp {
            AttendanceService.recordConsent(studentId, status = "withdrawn", sourceNote = "Admin withdrawal")
            _consent.value = AttendanceService.fetchCurrentConsent(studentId)
            "Consent withdrawn."
        }
    }

    fun grantConsent(studentId: String) {
        runOp {
            AttendanceService.recordConsent(studentId, status = "granted", sourceNote = "Admin re-grant")
            _consent.value = AttendanceService.fetchCurrentConsent(studentId)
            "Consent recorded."
        }
    }

    fun anonymise(studentId: String, onDone: () -> Unit) {
        runOp(onDone) {
            AttendanceService.anonymiseStudent(studentId)
            "Student anonymised."
        }
    }

    fun erase(studentId: String, onDone: () -> Unit) {
        runOp(onDone) {
            AttendanceService.eraseStudent(studentId)
            "Student data erased."
        }
    }

    fun export(context: Context, studentId: String) {
        viewModelScope.launch {
            _busy.value = true
            _error.value = null
            _message.value = null
            runCatching {
                val json = AttendanceService.exportStudentPersonalData(studentId)
                val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                val fileName = "pdpa-export-$studentId-$date.json"
                val dir = File(context.cacheDir, "exports").apply { mkdirs() }
                // Purge prior PII exports so they don't accumulate unencrypted on a shared device.
                dir.listFiles()?.forEach { it.delete() }
                val file = File(dir, fileName)
                withContext(Dispatchers.IO) { file.writeText(json) }
                val uri = FileProvider.getUriForFile(
                    context, "${context.packageName}.fileprovider", file
                )
                val share = Intent(Intent.ACTION_SEND).apply {
                    type = "application/json"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, fileName)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startActivity(Intent.createChooser(share, "Export student data"))
            }.onFailure { _error.value = it.message ?: "Export failed" }
            _busy.value = false
        }
    }

    private fun runOp(onDone: (() -> Unit)? = null, block: suspend () -> String) {
        viewModelScope.launch {
            _busy.value = true
            _error.value = null
            _message.value = null
            runCatching { block() }
                .onSuccess { _message.value = it; onDone?.invoke() }
                .onFailure { _error.value = it.message ?: "Operation failed" }
            _busy.value = false
        }
    }

    fun clearMessages() { _message.value = null; _error.value = null }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentPdpaSheet(
    studentId: String,
    fullName: String,
    onDismiss: () -> Unit,
    onStudentRemoved: () -> Unit,
    vm: StudentPdpaViewModel = viewModel()
) {
    val context = LocalContext.current
    LaunchedEffect(studentId) { vm.load(studentId) }

    val consent by vm.consent.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val busy by vm.busy.collectAsState()
    val message by vm.message.collectAsState()
    val error by vm.error.collectAsState()

    var confirmAnonymise by remember { mutableStateOf(false) }
    var confirmErase by remember { mutableStateOf(false) }

    val dataConsent = consent.firstOrNull { it.consentType == "data_collection" }
    val isGranted = dataConsent?.status == "granted"

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text(fullName, style = MaterialTheme.typography.headlineSmall)
            Text("Privacy & data (PDPA)", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))

            // ---- Consent status ----
            Text("Consent", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            if (isLoading) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            } else if (dataConsent == null) {
                Text("No consent record on file.", color = MaterialTheme.colorScheme.error)
            } else {
                val color = if (isGranted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                Text(
                    "Data collection: ${dataConsent.status} (${dataConsent.method})",
                    color = color
                )
                dataConsent.noticeVersion?.let {
                    Text("Notice version $it", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isGranted) {
                    OutlinedButton(onClick = { vm.withdrawConsent(studentId) }, enabled = !busy) {
                        Text("Withdraw consent")
                    }
                } else {
                    OutlinedButton(onClick = { vm.grantConsent(studentId) }, enabled = !busy) {
                        Text("Record consent")
                    }
                }
            }

            HorizontalDivider(Modifier.padding(vertical = 16.dp))

            // ---- Subject access export ----
            Text("Subject-access request", style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text("Export all personal data held about this student as JSON.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Button(onClick = { vm.export(context, studentId) }, enabled = !busy) {
                Text("Export this student's data")
            }

            HorizontalDivider(Modifier.padding(vertical = 16.dp))

            // ---- Erasure ----
            Text("Erasure", style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(4.dp))
            Text("Anonymise keeps anonymous attendance counts. Erase is a hard delete and cannot be undone.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { confirmAnonymise = true }, enabled = !busy) {
                    Text("Anonymise")
                }
                Button(
                    onClick = { confirmErase = true },
                    enabled = !busy,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) { Text("Erase") }
            }

            Spacer(Modifier.height(12.dp))
            message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

            Spacer(Modifier.height(32.dp))
        }
    }

    if (confirmAnonymise) {
        AlertDialog(
            onDismissRequest = { confirmAnonymise = false },
            title = { Text("Anonymise student") },
            text = { Text("Redact \"$fullName\"'s personal data while keeping anonymous attendance records? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmAnonymise = false
                    vm.anonymise(studentId) { onStudentRemoved() }
                }) { Text("Anonymise") }
            },
            dismissButton = { TextButton(onClick = { confirmAnonymise = false }) { Text("Cancel") } }
        )
    }

    if (confirmErase) {
        AlertDialog(
            onDismissRequest = { confirmErase = false },
            title = { Text("Erase student") },
            text = { Text("Permanently delete all of \"$fullName\"'s data including audit snapshots? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmErase = false
                    vm.erase(studentId) { onStudentRemoved() }
                }) { Text("Erase", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmErase = false }) { Text("Cancel") } }
        )
    }
}

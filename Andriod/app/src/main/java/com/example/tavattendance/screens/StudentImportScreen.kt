package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import com.example.tavattendance.core.CsvStudentParser
import com.example.tavattendance.data.models.StudentInsert
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class StudentImportViewModel(app: Application) : AndroidViewModel(app) {
    private val _isImporting = MutableStateFlow(false)
    val isImporting = _isImporting.asStateFlow()

    private val _result = MutableStateFlow<String?>(null)
    val result = _result.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    /**
     * Imports parsed rows, writing a granted data_collection consent record for each student.
     * Blocks if consent has not been attested. Surfaces failures rather than swallowing them.
     */
    fun import(rows: List<StudentInsert>, consentAttested: Boolean, onDone: () -> Unit) {
        if (!consentAttested) {
            _error.value = "Tick the consent attestation before importing."
            return
        }
        if (rows.isEmpty()) {
            _error.value = "Nothing to import."
            return
        }
        viewModelScope.launch {
            _isImporting.value = true
            _error.value = null
            _result.value = null
            var ok = 0
            val failures = mutableListOf<String>()
            val version = runCatching { AttendanceService.fetchPrivacyNotice()?.version }.getOrNull()
            for (row in rows) {
                runCatching {
                    val student = AttendanceService.createStudent(row)
                    AttendanceService.recordConsent(
                        studentId = student.id,
                        status = "granted",
                        noticeVersion = version,
                        sourceNote = "Bulk CSV import"
                    )
                }.onSuccess { ok++ }
                    .onFailure { failures.add("${row.fullName}: ${it.message ?: "failed"}") }
            }
            _isImporting.value = false
            if (failures.isEmpty()) {
                _result.value = "Imported $ok student(s) with consent recorded."
                onDone()
            } else {
                _result.value = "Imported $ok student(s)."
                _error.value = "Failed ${failures.size}:\n" + failures.take(5).joinToString("\n")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentImportScreen(
    onBack: () -> Unit,
    onImported: () -> Unit,
    vm: StudentImportViewModel = viewModel()
) {
    var csvText by remember { mutableStateOf("") }
    var consentAttested by remember { mutableStateOf(false) }
    val parsed = remember(csvText) { CsvStudentParser.parse(csvText) }

    val isImporting by vm.isImporting.collectAsState()
    val result by vm.result.collectAsState()
    val error by vm.error.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Import Students") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "Paste CSV. First row is a header and is ignored. Columns: full_name, school, year_of_study.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            OutlinedTextField(
                value = csvText,
                onValueChange = { csvText = it },
                label = { Text("CSV") },
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp)
            )

            if (parsed.rows.isNotEmpty()) {
                Text("${parsed.rows.size} student(s) detected", fontWeight = FontWeight.Medium)
                LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp)) {
                    items(parsed.rows) { r ->
                        val detail = listOfNotNull(r.school, r.yearOfStudy).joinToString(" · ")
                        ListItem(
                            headlineContent = { Text(r.fullName) },
                            supportingContent = { if (detail.isNotBlank()) Text(detail) }
                        )
                        HorizontalDivider()
                    }
                }
            }
            if (parsed.warnings.isNotEmpty()) {
                Text(
                    parsed.warnings.joinToString("\n"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            Row(verticalAlignment = Alignment.Top) {
                Checkbox(checked = consentAttested, onCheckedChange = { consentAttested = it })
                Spacer(Modifier.width(4.dp))
                Column {
                    Text(
                        "Parent/guardian consent obtained for every student in this file",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        "Required under PDPA. A consent record is logged for each imported student.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            result?.let {
                Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium)
            }

            Button(
                onClick = { vm.import(parsed.rows, consentAttested) { onImported() } },
                enabled = !isImporting && parsed.rows.isNotEmpty() && consentAttested,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (isImporting) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text("Import ${parsed.rows.size} student(s)")
            }
        }
    }
}

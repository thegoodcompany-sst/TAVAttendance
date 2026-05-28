package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.AttendanceHistoryRecord
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.*

class StudentProfileViewModel(app: Application) : AndroidViewModel(app) {
    private val _history = MutableStateFlow<List<AttendanceHistoryRecord>>(emptyList())
    val history = _history.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    fun load(studentId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            val since30Days = Instant.now().minusSeconds(30L * 24 * 3600).toString()
            runCatching {
                _history.value = AttendanceService.fetchStudentAttendanceHistory(
                    studentId = studentId, limit = 100, since = since30Days
                )
            }.onFailure { _error.value = it.message ?: "Failed to load history" }
            _isLoading.value = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentProfileSheet(
    studentId: String,
    fullName: String,
    onDismiss: () -> Unit,
    vm: StudentProfileViewModel = viewModel()
) {
    LaunchedEffect(studentId) { vm.load(studentId) }

    val history by vm.history.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val error by vm.error.collectAsState()

    val presentCount = history.count { it.status == AttendanceStatus.present }
    val lateCount = history.count { it.status == AttendanceStatus.late }
    val absentCount = history.count { it.status == AttendanceStatus.absent }
    val excusedCount = history.count { it.status == AttendanceStatus.excused }
    val attendanceRate = if (history.isNotEmpty())
        (presentCount + lateCount).toFloat() / history.size else 0f

    val isoFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val prettyFmt = SimpleDateFormat("MMM d, yyyy", Locale.US)
    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    fun formatDate(iso: String) = runCatching { prettyFmt.format(isoFmt.parse(iso)!!) }.getOrDefault(iso)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text(fullName, style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(16.dp))

            when {
                isLoading -> Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                error != null -> Column(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { vm.load(studentId) }) { Text("Retry") }
                }
                history.isEmpty() -> Text(
                    "No records in the last 30 days.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
                else -> {
                    // Stats card
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
                                Text("attendance", style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(bottom = 6.dp))
                                Spacer(Modifier.weight(1f))
                                Text("${history.size} sessions", style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(bottom = 6.dp))
                            }
                            // Progress bar — only render non-zero segments (weight(0f) crashes)
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

                    Spacer(Modifier.height(16.dp))
                    Text("Sessions (last 30 days)", style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))

                    LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 400.dp)) {
                        items(history, key = { it.id }) { record ->
                            val color = statusColor(record.status)
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Surface(shape = MaterialTheme.shapes.extraSmall, color = color,
                                    modifier = Modifier.size(10.dp)) {}
                                Spacer(Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(record.session.cls.name, style = MaterialTheme.typography.bodyMedium)
                                    Text(formatDate(record.session.sessionDate),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(
                                        record.status.name.replaceFirstChar { it.uppercase() },
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = color
                                    )
                                    record.markedAt?.let { ts ->
                                        runCatching { Date(Instant.parse(ts).toEpochMilli()) }.getOrNull()?.let { d ->
                                            Text(timeFmt.format(d), style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }
                            }
                            HorizontalDivider()
                        }
                    }
                }
            }
            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun RowScope.StatPill(value: Int, label: String, color: Color) {
    Column(
        modifier = Modifier.weight(1f),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("$value", style = MaterialTheme.typography.titleLarge, color = color)
        Text(label, style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

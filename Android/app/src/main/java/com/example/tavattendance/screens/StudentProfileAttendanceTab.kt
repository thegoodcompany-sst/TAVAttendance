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

@Composable
internal fun AttendanceTabContent(
    modifier: Modifier = Modifier,
    history: List<AttendanceHistoryRecord>,
    isLoading: Boolean,
    error: String?,
    presentCount: Int,
    lateCount: Int,
    absentCount: Int,
    attendanceRate: Float,
    formatDate: (String) -> String,
    timeFmt: SimpleDateFormat,
    onRetry: () -> Unit,
    includeStaffResults: Boolean,
    slips: List<ResultSlip>,
    slipsLoading: Boolean,
    slipsError: String?,
    onRetrySlips: () -> Unit,
    onAddResult: () -> Unit,
) {
    LazyColumn(modifier = modifier.fillMaxWidth()) {
        when {
            isLoading -> item {
                Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            error != null && history.isEmpty() -> item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(error, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = onRetry) { Text("Retry") }
                }
            }
            history.isEmpty() -> item {
                Text(
                    "No records in the last 30 days.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
            }
            else -> {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Row(modifier = Modifier.fillMaxWidth()) {
                                StatPill(presentCount, "Present", Color(0xFF34C759))
                                StatPill(lateCount, "Late", Color(0xFFFF9500))
                                StatPill(absentCount, "Absent", Color(0xFFFF3B30))
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
                                Text(
                                    "attendance",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(bottom = 6.dp)
                                )
                                Spacer(Modifier.weight(1f))
                                Text(
                                    "${history.size} sessions",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(bottom = 6.dp)
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth().height(8.dp)) {
                                val total = history.size.toFloat()
                                if (total > 0) {
                                    if (presentCount > 0) Surface(modifier = Modifier.weight(presentCount / total), color = Color(0xFF34C759)) {}
                                    if (lateCount > 0) Surface(modifier = Modifier.weight(lateCount / total), color = Color(0xFFFF9500)) {}
                                    if (absentCount > 0) Surface(modifier = Modifier.weight(absentCount / total), color = Color(0xFFFF3B30)) {}
                                }
                            }
                        }
                    }
                }

                item {
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "Sessions (last 30 days)",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(8.dp))
                }

                items(history, key = { "attendance-${it.id}" }) { record ->
                    val color = statusColor(record.status)
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = color,
                            modifier = Modifier.size(10.dp)
                        ) {}
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(record.session.cls.name, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                formatDate(record.session.sessionDate),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                record.status.name.replaceFirstChar { it.uppercase() },
                                style = MaterialTheme.typography.bodyMedium,
                                color = color
                            )
                            record.markedAt?.let { timestamp ->
                                runCatching { Date(Instant.parse(timestamp).toEpochMilli()) }
                                    .getOrNull()
                                    ?.let { markedDate ->
                                        Text(
                                            timeFmt.format(markedDate),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                            }
                        }
                    }
                    HorizontalDivider()
                }
            }
        }

        if (includeStaffResults) {
            item {
                Spacer(Modifier.height(16.dp))
                Text("Result Slips", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(8.dp))
            }
            when {
                slipsLoading -> item {
                    Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                slipsError != null && slips.isEmpty() -> item {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(slipsError, color = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = onRetrySlips) { Text("Retry") }
                    }
                }
                else -> {
                    if (slips.isEmpty()) {
                        item {
                            Text(
                                "No result slips yet.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(slips, key = { "slip-${it.id}" }) { slip ->
                            ResultSlipRow(slip, formatDate, showAck = false)
                            HorizontalDivider()
                        }
                    }
                    item {
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = onAddResult, modifier = Modifier.fillMaxWidth()) {
                            Text("Add Result Slip")
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun RowScope.StatPill(value: Int, label: String, color: Color) {
    Column(
        modifier = Modifier.weight(1f),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("$value", style = MaterialTheme.typography.titleLarge, color = color)
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

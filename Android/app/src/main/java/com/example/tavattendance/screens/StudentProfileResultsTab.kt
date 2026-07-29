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
internal fun ResultsTabContent(
    slips: List<ResultSlip>,
    isLoading: Boolean,
    error: String?,
    formatDate: (String) -> String,
    onRetry: () -> Unit,
    onAddResult: () -> Unit,
    isParentMode: Boolean
) {
    when {
        isLoading -> Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        error != null && slips.isEmpty() -> Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(error, color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(8.dp))
            Button(onClick = onRetry) { Text("Retry") }
        }
        else -> {
            LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
                if (slips.isEmpty()) {
                    item {
                        Text(
                            "No result slips yet.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    items(slips, key = { it.id }) { slip ->
                        ResultSlipRow(slip, formatDate, showAck = isParentMode)
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

@Composable
internal fun ResultSlipRow(
    slip: ResultSlip,
    formatDate: (String) -> String,
    showAck: Boolean
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(slip.subject ?: "—", style = MaterialTheme.typography.bodyMedium)
            slip.examName?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            slip.examDate?.let {
                Text(formatDate(it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            slip.fractionDisplay?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium)
            }
            if (showAck) {
                Text(
                    if (slip.isAcknowledged) "Acknowledged" else "Pending review",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (slip.isAcknowledged) Color(0xFF34C759) else Color(0xFFFF9500)
                )
            }
        }
    }
}

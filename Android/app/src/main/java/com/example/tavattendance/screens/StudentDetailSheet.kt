package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.ErrorRetry
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.core.asUserMessage
import com.example.tavattendance.data.models.AttendanceHistoryRecord
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.AttendanceStatusLabel
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.ClassYearSummary
import com.example.tavattendance.data.service.StudentYearSummary
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale

/**
 * Students-tab year detail. Rolling 12-month by-class summary + recent register
 * (cap 50). Separate from [StudentProfileSheet] (30-day roster/parent sheet) so
 * percentages never disagree across surfaces.
 */
class StudentDetailViewModel(app: Application) : AndroidViewModel(app) {
    private val _history = MutableStateFlow<List<AttendanceHistoryRecord>>(emptyList())
    val history = _history.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError = _loadError.asStateFlow()

    private var studentId: String = ""

    fun load(studentId: String) {
        this.studentId = studentId
        viewModelScope.launch {
            _isLoading.value = true
            _loadError.value = null
            // ~104 tuition sessions/year at Mon+Thu; 1000 leaves headroom for
            // multi-class students and test_mode days without a second page.
            runCatching {
                AttendanceService.fetchStudentAttendanceHistory(
                    studentId = studentId,
                    limit = 1000,
                    since = StudentYearSummary.windowStartIso()
                )
            }.onSuccess {
                _history.value = it
            }.onFailure {
                _loadError.value = it.asUserMessage("Couldn't load attendance")
            }
            _isLoading.value = false
        }
    }

    fun retry() {
        if (studentId.isNotEmpty()) load(studentId)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentDetailSheet(
    student: Student,
    isAdmin: Boolean,
    onDismiss: () -> Unit,
    vm: StudentDetailViewModel = viewModel(key = student.id)
) {
    TrackScreen("student_detail")
    LaunchedEffect(student.id) { vm.load(student.id) }

    val history by vm.history.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val loadError by vm.loadError.collectAsState()

    val classSummaries = remember(history) { StudentYearSummary.byClass(history) }
    val recentRegister = remember(history) { history.take(50) }

    val dateFmt = remember { SimpleDateFormat("MMM d, yyyy", Locale.US) }
    val isoFmt = remember { SimpleDateFormat("yyyy-MM-dd", Locale.US) }
    val timeFmt = remember { SimpleDateFormat("h:mm a", Locale.US) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        when {
            isLoading -> Box(
                modifier = Modifier.fillMaxWidth().height(240.dp),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
            loadError != null && history.isEmpty() -> Box(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                ErrorRetry(loadError!!, onRetry = { vm.retry() })
            }
            else -> LazyColumn(
                modifier = Modifier.fillMaxWidth().padding(bottom = 32.dp),
                contentPadding = PaddingValues(horizontal = 20.dp)
            ) {
                item {
                    Text(
                        student.fullName,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    val detail = listOfNotNull(student.school, student.yearOfStudy).joinToString(" · ")
                    if (detail.isNotBlank()) {
                        Text(
                            detail,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Spacer(Modifier.height(20.dp))
                    Text(
                        "Attendance by class (last 12 months)",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (!isAdmin) {
                        Text(
                            "Showing only the classes you teach.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                }

                if (classSummaries.isEmpty()) {
                    item {
                        Text(
                            "No sessions recorded for this student in the past year.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 12.dp)
                        )
                    }
                } else {
                    items(classSummaries, key = { it.className }) { summary ->
                        ClassYearSummaryRow(summary)
                        HorizontalDivider()
                    }
                }

                if (recentRegister.isNotEmpty()) {
                    item {
                        Spacer(Modifier.height(20.dp))
                        Text(
                            "Recent register",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                    items(recentRegister, key = { it.id }) { record ->
                        HistoryRegisterRow(
                            record = record,
                            dateLabel = formatIsoDate(record.session.sessionDate, isoFmt, dateFmt),
                            timeLabel = record.markedAt?.let { marked ->
                                runCatching {
                                    timeFmt.format(Date(Instant.parse(marked).toEpochMilli()))
                                }.getOrNull()
                            }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

@Composable
private fun ClassYearSummaryRow(summary: ClassYearSummary) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(summary.className, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text(
                "${summary.totalSessions} sessions · ${summary.presentCount} present · ${summary.lateCount} late · ${summary.absentCount} absent",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            pctLabel(summary.attendancePct),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = pctColor(summary.attendancePct),
            textAlign = TextAlign.End
        )
    }
}

@Composable
private fun HistoryRegisterRow(
    record: AttendanceHistoryRecord,
    dateLabel: String,
    timeLabel: String?
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = CircleShape,
            color = statusDotColor(record.status),
            modifier = Modifier.size(10.dp)
        ) {}
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(record.session.cls.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text(dateLabel, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                AttendanceStatusLabel.rosterText(record.status, record.absenceInformed),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = statusDotColor(record.status)
            )
            if (timeLabel != null) {
                Text(timeLabel, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private fun formatIsoDate(iso: String, isoFmt: SimpleDateFormat, prettyFmt: SimpleDateFormat): String =
    runCatching { prettyFmt.format(requireNotNull(isoFmt.parse(iso))) }.getOrDefault(iso)

/** Web PctBadge thresholds: ≥80 emerald, ≥60 amber, else rose. */
private fun pctColor(pct: Double?): Color {
    if (pct == null) return Color.Gray
    return when {
        pct >= 80 -> Color(0xFF34C759)
        pct >= 60 -> Color(0xFFFF9500)
        else -> Color(0xFFFF3B30)
    }
}

private fun pctLabel(pct: Double?): String {
    if (pct == null) return "—"
    return if (pct == pct.toLong().toDouble()) "${pct.toLong()}%" else String.format(Locale.US, "%.1f%%", pct)
}

private fun statusDotColor(status: AttendanceStatus): Color = when (status) {
    AttendanceStatus.present -> Color(0xFF34C759)
    AttendanceStatus.late -> Color(0xFFFF9500)
    AttendanceStatus.absent -> Color(0xFFFF3B30)
}

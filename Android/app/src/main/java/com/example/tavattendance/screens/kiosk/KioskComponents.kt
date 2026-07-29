package com.example.tavattendance.screens.kiosk

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.KioskEntry
import java.text.SimpleDateFormat
import java.util.*

@Composable
internal fun KioskCard(
    entry: KioskEntry,
    isPending: Boolean,
    isAdminMode: Boolean,
    onTap: () -> Unit,
    onAction: (KioskAction) -> Unit
) {
    val statusColor: Color = when (entry.status) {
        AttendanceStatus.present -> Color(0xFF34C759)
        AttendanceStatus.late -> Color(0xFFFF9500)
        AttendanceStatus.absent -> Color(0xFFFF3B30)
        AttendanceStatus.excused, null -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
    }

    val statusLabel = when (entry.status) {
        AttendanceStatus.present -> "On Time"
        AttendanceStatus.late -> "Late"
        AttendanceStatus.absent -> "Absent"
        AttendanceStatus.excused -> "Not Here"
        null -> "Not signed in"
    }

    val canTap = entry.status == null || entry.status == AttendanceStatus.excused ||
            (isAdminMode && (entry.status == AttendanceStatus.late || entry.status == AttendanceStatus.absent))

    val timeFmt = SimpleDateFormat("h:mm a", Locale.US)

    DropdownMenuCard(
        enabled = !isPending,
        canTap = canTap,
        onTap = onTap,
        contextMenuItems = buildList {
            if (isAdminMode) {
                if (entry.status != AttendanceStatus.late && entry.status != AttendanceStatus.absent) {
                    add("Mark as Late" to KioskAction.MarkLate)
                }
                if (entry.status == AttendanceStatus.late || entry.status == AttendanceStatus.present) {
                    add("Mark as Not Here" to KioskAction.MarkNotHere)
                }
                if (entry.status != AttendanceStatus.present && entry.status != null && entry.status != AttendanceStatus.excused) {
                    add("Mark as On Time" to KioskAction.MarkPresent)
                }
                if (entry.status != AttendanceStatus.absent) {
                    add("Mark as Absent" to KioskAction.MarkAbsent)
                }
            }
        },
        onMenuAction = onAction
    ) {
        Card(
            modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
        ) {
            Box(modifier = Modifier.fillMaxSize().padding(12.dp), contentAlignment = Alignment.Center) {
                if (isPending) {
                    CircularProgressIndicator()
                } else {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        // A11Y-04: status indicator with contentDescription so screen readers
                        // convey meaning without relying solely on colour.
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = statusColor,
                            modifier = Modifier
                                .size(12.dp)
                                .semantics { contentDescription = "${entry.fullName}: $statusLabel" }
                        ) {}
                        Spacer(Modifier.height(8.dp))
                        Text(
                            entry.fullName,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                            maxLines = 2
                        )
                        if (entry.status != null) {
                            Spacer(Modifier.height(4.dp))
                            Text(statusLabel, style = MaterialTheme.typography.labelSmall, color = statusColor)
                            if (entry.status != AttendanceStatus.excused && entry.markedAt != null) {
                                val markedDate = runCatching {
                                    Date(java.time.Instant.parse(entry.markedAt).toEpochMilli())
                                }.getOrNull()
                                markedDate?.let {
                                    Text(
                                        timeFmt.format(it),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            if (isAdminMode && entry.status != AttendanceStatus.present && entry.status != AttendanceStatus.excused) {
                                Text(
                                    "Tap → On Time",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// DropdownMenuCard
// ---------------------------------------------------------------------------

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun DropdownMenuCard(
    enabled: Boolean,
    canTap: Boolean,
    onTap: () -> Unit,
    contextMenuItems: List<Pair<String, KioskAction>>,
    onMenuAction: (KioskAction) -> Unit,
    content: @Composable () -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                enabled = enabled,
                onClick = {
                    if (canTap) onTap()
                    else if (contextMenuItems.isNotEmpty()) menuExpanded = true
                },
                onLongClick = { if (contextMenuItems.isNotEmpty()) menuExpanded = true }
            )
    ) {
        content()
        if (contextMenuItems.isNotEmpty()) {
            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                contextMenuItems.forEach { (label, action) ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                label,
                                color = if (action == KioskAction.MarkAbsent)
                                    MaterialTheme.colorScheme.error
                                else
                                    MaterialTheme.colorScheme.onSurface
                            )
                        },
                        onClick = { onMenuAction(action); menuExpanded = false }
                    )
                }
            }
        }
    }
}

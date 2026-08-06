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
import com.example.tavattendance.data.models.AttendanceStatusLabel
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
        null -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
    }

    val statusLabel = AttendanceStatusLabel.text(entry.status, entry.absenceInformed)

    val canTap = entry.status == null ||
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
                if (entry.status != null) {
                    add("Clear attendance" to KioskAction.Clear)
                }
                if (entry.status != AttendanceStatus.present && entry.status != null) {
                    add("Mark as On Time" to KioskAction.MarkPresent)
                }
                // Allow correcting informed/no-notice without clearing first.
                if (entry.status != AttendanceStatus.absent || entry.absenceInformed != true) {
                    add("Absent — Informed" to KioskAction.MarkAbsentInformed)
                }
                if (entry.status != AttendanceStatus.absent || entry.absenceInformed != false) {
                    add("Absent — Did not inform" to KioskAction.MarkAbsentNoNotice)
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
                        Spacer(Modifier.height(4.dp))
                        Text(statusLabel, style = MaterialTheme.typography.labelSmall, color = statusColor)
                        if (entry.status != null) {
                            if (entry.markedAt != null) {
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
                            if (isAdminMode && entry.status != AttendanceStatus.present) {
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
                    val destructive = action == KioskAction.MarkAbsentInformed ||
                        action == KioskAction.MarkAbsentNoNotice
                    DropdownMenuItem(
                        text = {
                            Text(
                                label,
                                color = if (destructive)
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

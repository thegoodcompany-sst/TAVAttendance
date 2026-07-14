package com.example.tavattendance.screens.kiosk

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.data.models.AttendanceStatus
import com.example.tavattendance.data.models.RosterEntry
import com.example.tavattendance.data.models.Session
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.launch

/**
 * Internal Study Space (drop-in room) attendance — migration 015.
 *
 * Present / Not Here only (no late/absent). Roster = ALL active students. This attendance is
 * internal reference ONLY and is EXCLUDED from every report, report card, and parent view
 * (see CLAUDE.md "Study Space tracking" invariant). Full-screen overlay shown from the kiosk
 * when the `study_space_tracking` flag is on.
 */
@Composable
fun StudySpaceScreen(onDismiss: () -> Unit) {
    TrackScreen("study_space")
    val scope = rememberCoroutineScope()
    var session by remember { mutableStateOf<Session?>(null) }
    var roster by remember { mutableStateOf<List<RosterEntry>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var pendingIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        isLoading = true
        runCatching { AttendanceService.loadStudySpace() }
            .onSuccess { (s, r) -> session = s; roster = r; errorMessage = null }
            .onFailure { errorMessage = "Couldn't load the Study Space roster." }
        isLoading = false
    }

    val presentCount = roster.count { it.status == AttendanceStatus.present }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize()) {
            Surface(shadowElevation = 2.dp) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Study Space", style = MaterialTheme.typography.headlineSmall)
                        if (roster.isNotEmpty()) {
                            Text(
                                "$presentCount / ${roster.size} present",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    TextButton(onClick = onDismiss) { Text("Done") }
                }
            }

            when {
                isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                errorMessage != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        errorMessage ?: "",
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(32.dp)
                    )
                }
                roster.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        "No active students to track.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(32.dp)
                    )
                }
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 160.dp),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize()
                ) {
                    items(roster, key = { it.studentId }) { entry ->
                        StudySpaceCard(
                            entry = entry,
                            isPending = entry.studentId in pendingIds
                        ) {
                            val s = session
                            if (s != null) {
                                val newStatus =
                                    if (entry.status == AttendanceStatus.present) AttendanceStatus.excused
                                    else AttendanceStatus.present
                                pendingIds = pendingIds + entry.studentId
                                scope.launch {
                                    runCatching {
                                        AttendanceService.markAttendance(s.id, entry.studentId, newStatus)
                                    }.onSuccess {
                                        roster = roster.map {
                                            if (it.studentId == entry.studentId) it.copy(status = newStatus) else it
                                        }
                                    }.onFailure {
                                        errorMessage = "Couldn't update attendance. Check your connection and try again."
                                    }
                                    pendingIds = pendingIds - entry.studentId
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StudySpaceCard(entry: RosterEntry, isPending: Boolean, onTap: () -> Unit) {
    val isPresent = entry.status == AttendanceStatus.present
    val present = Color(0xFF2E7D32)
    val container =
        if (isPresent) present.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant

    Card(
        colors = CardDefaults.cardColors(containerColor = container),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 120.dp)
            .clickable(enabled = !isPending) { onTap() }
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                entry.fullName,
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(Modifier.height(6.dp))
            if (isPending) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
            } else {
                Text(
                    if (isPresent) "Present" else "Not Here",
                    style = MaterialTheme.typography.labelMedium,
                    color = if (isPresent) present else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

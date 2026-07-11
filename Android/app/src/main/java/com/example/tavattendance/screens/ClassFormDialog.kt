package com.example.tavattendance.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.tavattendance.data.models.ClassInsert
import com.example.tavattendance.data.models.ResultSubject
import com.example.tavattendance.data.models.TAVClass

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassFormDialog(
    title: String,
    initial: TAVClass? = null,
    onDismiss: () -> Unit,
    onSave: (ClassInsert) -> Unit
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var subject by remember { mutableStateOf(ResultSubject.normalizing(initial?.subject)) }
    var level by remember { mutableStateOf(initial?.level ?: "") }
    var scheduleDay by remember { mutableStateOf(initial?.scheduleDay ?: "") }
    var scheduleTime by remember { mutableStateOf(initial?.scheduleTime?.take(5) ?: "") }
    var durationMinutes by remember { mutableStateOf((initial?.durationMinutes ?: 60).toString()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name *") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                var subjectExpanded by remember { mutableStateOf(false) }
                ExposedDropdownMenuBox(
                    expanded = subjectExpanded,
                    onExpandedChange = { subjectExpanded = it }
                ) {
                    OutlinedTextField(
                        value = subject?.displayName ?: "—",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Subject") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = subjectExpanded) },
                        modifier = Modifier.fillMaxWidth().menuAnchor()
                    )
                    ExposedDropdownMenu(
                        expanded = subjectExpanded,
                        onDismissRequest = { subjectExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("—") },
                            onClick = { subject = null; subjectExpanded = false }
                        )
                        ResultSubject.entries.forEach { s ->
                            DropdownMenuItem(
                                text = { Text(s.displayName) },
                                onClick = { subject = s; subjectExpanded = false }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = level,
                    onValueChange = { level = it },
                    label = { Text("Level") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = scheduleDay,
                    onValueChange = { scheduleDay = it },
                    label = { Text("Schedule Day (e.g. Monday)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = scheduleTime,
                    onValueChange = { scheduleTime = it },
                    label = { Text("Schedule Time (HH:mm)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = durationMinutes,
                    onValueChange = { durationMinutes = it },
                    label = { Text("Duration (minutes)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        ClassInsert(
                            name = name.trim(),
                            subject = subject?.raw,
                            level = level.trim().ifBlank { null },
                            scheduleDay = scheduleDay.trim().ifBlank { null },
                            scheduleTime = scheduleTime.trim().ifBlank { null },
                            durationMinutes = durationMinutes.trim().toIntOrNull() ?: 60
                        )
                    )
                },
                enabled = name.isNotBlank()
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

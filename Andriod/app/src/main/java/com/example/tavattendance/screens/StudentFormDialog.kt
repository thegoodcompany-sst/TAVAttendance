package com.example.tavattendance.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.models.StudentInsert

/**
 * @param requireConsent  when true (single-student create), the admin must tick the
 *   parent/guardian-consent attestation before the form can be saved. The boolean is
 *   passed back to the caller so it can write a consent_records row.
 * @param onSave  (student, consentAttested) — consentAttested is only meaningful when
 *   requireConsent is true.
 */
@Composable
fun StudentFormDialog(
    title: String,
    initial: Student? = null,
    requireConsent: Boolean = false,
    onDismiss: () -> Unit,
    onSave: (StudentInsert, Boolean) -> Unit
) {
    var fullName by remember { mutableStateOf(initial?.fullName ?: "") }
    var school by remember { mutableStateOf(initial?.school ?: "") }
    var yearOfStudy by remember { mutableStateOf(initial?.yearOfStudy ?: "") }
    var consentAttested by remember { mutableStateOf(false) }

    val canSave = fullName.isNotBlank() && (!requireConsent || consentAttested)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = fullName,
                    onValueChange = { fullName = it },
                    label = { Text("Full Name *") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = school,
                    onValueChange = { school = it },
                    label = { Text("School") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = yearOfStudy,
                    onValueChange = { yearOfStudy = it },
                    label = { Text("Year of Study") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                if (requireConsent) {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(
                            checked = consentAttested,
                            onCheckedChange = { consentAttested = it }
                        )
                        Spacer(Modifier.width(4.dp))
                        Column {
                            Text(
                                "Parent/guardian consent obtained for collection of this child's data",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                "Required under Singapore PDPA before the centre may hold a minor's data.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        StudentInsert(
                            fullName = fullName.trim(),
                            school = school.trim().ifBlank { null },
                            yearOfStudy = yearOfStudy.trim().ifBlank { null }
                        ),
                        consentAttested
                    )
                },
                enabled = canSave
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

package com.example.tavattendance.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.models.StudentInsert

@Composable
fun StudentFormDialog(
    title: String,
    initial: Student? = null,
    onDismiss: () -> Unit,
    onSave: (StudentInsert) -> Unit
) {
    var fullName by remember { mutableStateOf(initial?.fullName ?: "") }
    var school by remember { mutableStateOf(initial?.school ?: "") }
    var yearOfStudy by remember { mutableStateOf(initial?.yearOfStudy ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
                        )
                    )
                },
                enabled = fullName.isNotBlank()
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

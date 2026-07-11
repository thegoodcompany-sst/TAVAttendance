package com.example.tavattendance.screens

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.data.models.GradeBands
import com.example.tavattendance.data.models.ResultSubject
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.service.AttendanceService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Tutor-facing Students tab: student list with per-subject grade entry. RLS limits the
 * list to students enrolled in the tutor's assigned classes; the subjects offered are the
 * normalized subjects of those classes (migration 023).
 */
class StudentResultsViewModel(app: Application) : AndroidViewModel(app) {
    private val _students = MutableStateFlow<List<Student>>(emptyList())
    val students = _students.asStateFlow()

    private val _subjects = MutableStateFlow<List<ResultSubject>>(emptyList())
    val subjects = _subjects.asStateFlow()

    // studentId -> subject -> grade
    private val _grades = MutableStateFlow<Map<String, Map<ResultSubject, String>>>(emptyMap())
    val grades = _grades.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            runCatching {
                val students = AttendanceService.fetchAllStudents()
                val subjects = AttendanceService.fetchMyClasses()
                    .mapNotNull { ResultSubject.normalizing(it.subject) }
                    .distinct()
                    .sortedBy { it.raw }
                val grades = AttendanceService.fetchStudentResults()
                    .mapNotNull { r -> ResultSubject.fromRaw(r.subject)?.let { r.studentId to (it to r.grade) } }
                    .groupBy({ it.first }, { it.second })
                    .mapValues { (_, pairs) -> pairs.toMap() }
                Triple(students, subjects, grades)
            }.onSuccess { (students, subjects, grades) ->
                _students.value = students
                _subjects.value = subjects
                _grades.value = grades
            }.onFailure { e ->
                _error.value = e.localizedMessage ?: e.javaClass.simpleName
            }
            _isLoading.value = false
        }
    }

    /** Persist a grade change; on success update local state. Returns null on success,
     * or an error message to show (caller reverts the picker). */
    suspend fun saveGrade(studentId: String, subject: ResultSubject, grade: String?): String? =
        runCatching {
            if (grade.isNullOrEmpty()) {
                AttendanceService.deleteStudentResult(studentId, subject)
            } else {
                AttendanceService.upsertStudentResult(studentId, subject, grade)
            }
        }.fold(
            onSuccess = {
                val forStudent = _grades.value[studentId].orEmpty().toMutableMap()
                if (grade.isNullOrEmpty()) forStudent.remove(subject) else forStudent[subject] = grade
                _grades.value = _grades.value + (studentId to forStudent)
                null
            },
            onFailure = { it.localizedMessage ?: it.javaClass.simpleName }
        )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudentResultsScreen(vm: StudentResultsViewModel = viewModel()) {
    val students by vm.students.collectAsState()
    val subjects by vm.subjects.collectAsState()
    val grades by vm.grades.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val error by vm.error.collectAsState()

    var selected by remember { mutableStateOf<Student?>(null) }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Students") }) }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                error != null -> Column(
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(error!!, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = { vm.load() }) { Text("Retry") }
                }
                students.isEmpty() -> Text(
                    "Students enrolled in your classes will appear here.",
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(students, key = { it.id }) { student ->
                        ResultRow(student, grades[student.id].orEmpty()) { selected = student }
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    selected?.let { student ->
        ResultEntrySheet(
            student = student,
            subjects = subjects,
            grades = grades[student.id].orEmpty(),
            onSave = { subject, grade -> vm.saveGrade(student.id, subject, grade) },
            onDismiss = { selected = null }
        )
    }
}

@Composable
private fun ResultRow(student: Student, grades: Map<ResultSubject, String>, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(student.fullName) },
        supportingContent = {
            val detail = listOfNotNull(student.school, student.yearOfStudy).joinToString(" · ")
            if (detail.isNotBlank()) Text(detail)
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (grades.isNotEmpty()) {
                    Text(
                        text = grades.entries.sortedBy { it.key.raw }
                            .joinToString("  ") { "${it.key.raw}: ${it.value}" },
                        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        modifier = Modifier.clickable { onClick() }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ResultEntrySheet(
    student: Student,
    subjects: List<ResultSubject>,
    grades: Map<ResultSubject, String>,
    onSave: suspend (ResultSubject, String?) -> String?,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(student.fullName, style = MaterialTheme.typography.headlineSmall)
            if (subjects.isEmpty()) {
                Text(
                    "None of your assigned classes has a subject set, so there is nothing to grade. Ask an admin to set the class subject.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text("Latest Grades", style = MaterialTheme.typography.labelLarge)
                subjects.forEach { subject ->
                    GradeRow(
                        student = student,
                        subject = subject,
                        initialGrade = grades[subject],
                        onSave = onSave
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GradeRow(
    student: Student,
    subject: ResultSubject,
    initialGrade: String?,
    onSave: suspend (ResultSubject, String?) -> String?
) {
    var grade by remember(subject) { mutableStateOf(initialGrade ?: "") }
    var expanded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    // Primary (PSLE AL) vs secondary (O-Level) band first, based on year_of_study; both
    // offered because the field is free text.
    val orderedBands = if (student.isPrimaryLevel == true) {
        listOf("Primary (AL)" to GradeBands.primary, "Secondary (O-Level)" to GradeBands.secondary)
    } else {
        listOf("Secondary (O-Level)" to GradeBands.secondary, "Primary (AL)" to GradeBands.primary)
    }

    fun select(newValue: String) {
        val oldValue = grade
        grade = newValue
        expanded = false
        scope.launch {
            val err = onSave(subject, newValue.ifEmpty { null })
            if (err != null) {
                error = "Couldn't save ${subject.displayName} grade: $err"
                grade = oldValue
            } else {
                error = null
            }
        }
    }

    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = grade.ifEmpty { "Not graded" },
            onValueChange = {},
            readOnly = true,
            label = { Text(subject.displayName) },
            isError = error != null,
            supportingText = error?.let { { Text(it, color = MaterialTheme.colorScheme.error) } },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor()
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("Not graded") }, onClick = { select("") })
            orderedBands.forEach { (label, band) ->
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(label, style = MaterialTheme.typography.labelSmall) },
                    enabled = false,
                    onClick = {}
                )
                band.forEach { g ->
                    DropdownMenuItem(text = { Text(g) }, onClick = { select(g) })
                }
            }
        }
    }
}

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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.auth.AuthViewModel
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ParentDashboardViewModel(app: Application) : AndroidViewModel(app) {
    private val _children = MutableStateFlow<List<Student>>(emptyList())
    val children = _children.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    // A load failure is distinct from "no children linked" — an empty list because the
    // request threw would otherwise read as "you have no children", hiding the error.
    private val _loadFailed = MutableStateFlow(false)
    val loadFailed = _loadFailed.asStateFlow()

    fun loadChildren() {
        viewModelScope.launch {
            _isLoading.value = true
            _loadFailed.value = false
            // RLS scopes students to this parent's own children (002_rls.sql).
            runCatching { _children.value = AttendanceService.fetchAllStudents() }
                .onFailure { _loadFailed.value = true }
            _isLoading.value = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ParentDashboardScreen(
    authViewModel: AuthViewModel,
    vm: ParentDashboardViewModel = viewModel()
) {
    val flags by FeatureFlags.flags.collectAsState()
    val portalEnabled = flags[FeatureFlags.PARENT_PORTAL] == true

    val children by vm.children.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val loadFailed by vm.loadFailed.collectAsState()

    var selectedChild by remember { mutableStateOf<Student?>(null) }

    // Only hit the network when the portal is live.
    LaunchedEffect(portalEnabled) { if (portalEnabled) vm.loadChildren() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (portalEnabled) "My Children" else "TAVA Attendance") },
                actions = { TextButton(onClick = { authViewModel.signOut() }) { Text("Sign Out") } }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                !portalEnabled -> CenteredMessage(
                    title = "Coming Soon",
                    body = "Your child's attendance history is being prepared. You'll be able to view it here soon."
                )
                isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                loadFailed -> Column(
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        "We couldn't load your children's information. Please check your connection and try again.",
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { vm.loadChildren() }) { Text("Retry") }
                }
                children.isEmpty() -> CenteredMessage(
                    title = "No Children Linked",
                    body = "No students are linked to your account yet. Please contact the centre."
                )
                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(children, key = { it.id }) { child ->
                        ListItem(
                            headlineContent = { Text(child.fullName) },
                            supportingContent = child.yearOfStudy?.let { { Text(it) } },
                            trailingContent = {
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                            },
                            modifier = Modifier.clickable { selectedChild = child }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    selectedChild?.let { child ->
        StudentProfileSheet(
            studentId = child.id,
            fullName = child.fullName,
            onDismiss = { selectedChild = null }
        )
    }
}

@Composable
private fun BoxScope.CenteredMessage(title: String, body: String) {
    Column(
        modifier = Modifier.align(Alignment.Center).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        Text(
            body,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

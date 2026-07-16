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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.example.tavattendance.auth.AuthViewModel
import com.example.tavattendance.auth.BiometricToggleAction
import com.example.tavattendance.data.models.Dismissal
import com.example.tavattendance.data.models.Student
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ParentDashboardViewModel(app: Application) : AndroidViewModel(app) {
    private val _children = MutableStateFlow<List<Student>>(emptyList())
    val children = _children.asStateFlow()

    // Today's dismissals still awaiting a safely-home confirmation (migration 030).
    private val _pendingDismissals = MutableStateFlow<List<Dismissal>>(emptyList())
    val pendingDismissals = _pendingDismissals.asStateFlow()

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
            // Safely-home is best-effort decoration; a failure here must not
            // hide the children list.
            runCatching {
                _pendingDismissals.value =
                    AttendanceService.awaitingSafelyHome(AttendanceService.fetchTodayDismissals())
            }
            _isLoading.value = false
        }
    }

    fun markSafelyHome(dismissalId: String) {
        viewModelScope.launch {
            runCatching { AttendanceService.markSafelyHome(dismissalId) }
                .onSuccess { _pendingDismissals.value = _pendingDismissals.value.filter { it.id != dismissalId } }
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
    val pushEnabled = flags[FeatureFlags.PUSH_NOTIFICATIONS] == true

    val children by vm.children.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val loadFailed by vm.loadFailed.collectAsState()
    val pendingDismissals by vm.pendingDismissals.collectAsState()

    var selectedChild by remember { mutableStateOf<Student?>(null) }

    // Only hit the network when the portal is live.
    LaunchedEffect(portalEnabled) { if (portalEnabled) vm.loadChildren() }

    // Dismissal pushes (flag push_notifications) need POST_NOTIFICATIONS on API 33+.
    val notifPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {}
    LaunchedEffect(pushEnabled) {
        if (pushEnabled && android.os.Build.VERSION.SDK_INT >= 33) {
            notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (portalEnabled) "My Children" else "TAVA Attendance") },
                actions = {
                    BiometricToggleAction()
                    TextButton(onClick = { authViewModel.signOut() }) { Text("Sign Out") }
                }
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
                    items(pendingDismissals, key = { "dismissal-${it.id}" }) { dismissal ->
                        SafelyHomeCard(
                            dismissal = dismissal,
                            childName = children.firstOrNull { it.id == dismissal.studentId }?.fullName
                                ?: "Your child",
                            onConfirm = { vm.markSafelyHome(dismissal.id) }
                        )
                    }
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
private fun SafelyHomeCard(dismissal: Dismissal, childName: String, onConfirm: () -> Unit) {
    val time = dismissal.dismissedAt?.let {
        runCatching {
            java.time.OffsetDateTime.parse(it)
                .atZoneSameInstant(java.time.ZoneId.systemDefault())
                .format(java.time.format.DateTimeFormatter.ofPattern("h:mm a"))
        }.getOrNull()
    }
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                if (time != null) "$childName was dismissed at $time."
                else "$childName was dismissed today.",
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(Modifier.height(12.dp))
            Button(onClick = onConfirm) { Text("Mark safely home") }
        }
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

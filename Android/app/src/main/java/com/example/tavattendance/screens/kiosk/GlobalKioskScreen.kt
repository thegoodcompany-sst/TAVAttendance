package com.example.tavattendance.screens.kiosk

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.core.TrackScreen
import com.example.tavattendance.data.service.FeatureFlags
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlobalKioskScreen(
    onExitKiosk: () -> Unit,
    vm: GlobalKioskViewModel = viewModel()
) {
    TrackScreen("kiosk")
    val entries by vm.entries.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val pendingIds by vm.pendingIds.collectAsState()
    val showPinUnlock by vm.showPinUnlock.collectAsState()
    val showSettings by vm.showSettings.collectAsState()
    val snackbarMessage by vm.snackbarMessage.collectAsState()
    val loadError by vm.loadError.collectAsState()

    // Collect the derived authorization state so lock/unlock changes recompose the UI.
    val isAdminMode by vm.isAdminMode.collectAsState()

    // Study Space (migration 015): flag-gated entry to the internal drop-in tracker.
    val featureFlags by FeatureFlags.flags.collectAsState()
    val studySpaceEnabled = featureFlags[FeatureFlags.STUDY_SPACE_TRACKING] == true
    var showStudySpace by remember { mutableStateOf(false) }

    // QR sign-in (flag qr_sign_in): student-facing like the card grid itself —
    // scanning only ever runs the same sign-in path a card tap would, so no admin gate.
    val qrSignInEnabled = featureFlags[FeatureFlags.QR_SIGN_IN] == true
    var showQrScanner by remember { mutableStateOf(false) }

    // System back must never be an escape hatch from a student-facing kiosk. An authenticated
    // admin gets an explicit Exit Kiosk control in the header below.
    BackHandler(enabled = true) {}

    // Kiosk admin authorization is process-local and is revoked when the activity stops.
    // Close any admin-only overlays at the same time so they cannot remain interactive when
    // the app returns in its newly locked state.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                showStudySpace = false
                showQrScanner = false
                vm.relockConfiguredKiosk()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val attending = entries.count { it.isAttending }
    val today = SimpleDateFormat("EEEE, MMMM d, yyyy", Locale.US).format(Date())

    // SP-06: Snackbar host for surfacing errors.
    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(snackbarMessage) {
        snackbarMessage?.let { msg ->
            snackbarHostState.showSnackbar(message = msg, duration = SnackbarDuration.Short)
            vm.clearSnackbar()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(innerPadding)
        ) {
            Column {
                // Header
                Surface(shadowElevation = 2.dp) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("Sign In", style = MaterialTheme.typography.headlineLarge)
                                if (isAdminMode) {
                                    Spacer(Modifier.width(8.dp))
                                    Surface(
                                        shape = MaterialTheme.shapes.extraSmall,
                                        color = MaterialTheme.colorScheme.tertiary
                                    ) {
                                        Text(
                                            "ADMIN",
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onTertiary,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                            Text(today, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (entries.isNotEmpty()) {
                            Text(
                                "$attending / ${entries.size} attended",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.width(16.dp))
                        }
                        if (isAdminMode && studySpaceEnabled) {
                            TextButton(onClick = {
                                vm.performAdminAction { showStudySpace = true }
                            }) {
                                Text("Study Space")
                            }
                        }
                        if (qrSignInEnabled && entries.isNotEmpty()) {
                            TextButton(onClick = { showQrScanner = true }) {
                                Text("Scan QR")
                            }
                        }
                        if (isAdminMode) {
                            TextButton(onClick = {
                                vm.performAdminAction(onExitKiosk)
                            }) {
                                Text("Exit Kiosk")
                            }
                        }
                        IconButton(
                            onClick = {
                                if (isAdminMode) vm.showSettingsDialog()
                                else vm.showPinUnlockDialog()
                            }
                        ) {
                            Icon(
                                if (isAdminMode) Icons.Default.Settings else Icons.Default.Lock,
                                contentDescription = if (isAdminMode) "Kiosk settings" else "Unlock kiosk"
                            )
                        }
                    }
                }

                when {
                    isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                    loadError != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
                            Text(loadError!!, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                            Spacer(Modifier.height(12.dp))
                            Button(onClick = { vm.loadEntries() }) { Text("Retry") }
                        }
                    }
                    entries.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            "No classes scheduled today.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
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
                        items(entries, key = { it.studentId }) { entry ->
                            KioskCard(
                                entry = entry,
                                isPending = entry.studentId in pendingIds,
                                isAdminMode = isAdminMode,
                                onTap = { vm.onCardTap(entry) },
                                onAction = { action -> vm.handleAction(entry, action) }
                            )
                        }
                    }
                }
            }

            if (showPinUnlock) {
                PinUnlockOverlay(
                    lockedUntil = vm.lockedUntil,
                    onDismiss = { vm.hidePinUnlockDialog() },
                    onAttempt = { pin -> vm.tryUnlock(pin) },
                )
            }

            if (showSettings) {
                KioskSettingsSheet(vm = vm, onDismiss = { vm.hideSettingsDialog() })
            }

            if (showStudySpace) {
                StudySpaceScreen(onDismiss = { showStudySpace = false })
            }

            if (showQrScanner) {
                QrScannerSheet(
                    onScan = { payload -> vm.handleScannedPayload(payload) },
                    onDismiss = { showQrScanner = false }
                )
            }
        }
    }
}

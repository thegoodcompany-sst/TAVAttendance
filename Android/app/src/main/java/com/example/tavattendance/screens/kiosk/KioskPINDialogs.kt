package com.example.tavattendance.screens.kiosk

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.StateFlow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun KioskSettingsSheet(vm: GlobalKioskViewModel, onDismiss: () -> Unit) {
    var showPinSetup by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Kiosk Settings", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(16.dp))

            if (vm.storedPin.isEmpty()) {
                Text("No PIN set — kiosk is always in admin mode", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { showPinSetup = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Set Kiosk PIN…")
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(shape = MaterialTheme.shapes.extraSmall, color = Color(0xFF34C759), modifier = Modifier.size(10.dp)) {}
                    Spacer(Modifier.width(8.dp))
                    Text("PIN configured")
                }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { showPinSetup = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Change PIN…")
                }
                Spacer(Modifier.height(4.dp))
                Button(onClick = { vm.lockKiosk(); onDismiss() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Lock Kiosk Now")
                }
                Spacer(Modifier.height(4.dp))
                OutlinedButton(
                    onClick = { vm.clearPin(); onDismiss() },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) {
                    Text("Remove PIN")
                }
            }
            Spacer(Modifier.height(32.dp))
        }
    }

    if (showPinSetup) {
        PinSetupDialog(
            onDismiss = { showPinSetup = false },
            onSave = { pin -> vm.setPin(pin); showPinSetup = false }
        )
    }
}

// ---------------------------------------------------------------------------
// PIN setup dialog
// ---------------------------------------------------------------------------

@Composable
internal fun PinSetupDialog(onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var step by remember { mutableIntStateOf(1) }
    var firstPin by remember { mutableStateOf("") }
    var secondPin by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }

    val current = if (step == 1) firstPin else secondPin

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (step == 1) "Enter new PIN" else "Confirm PIN") },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    repeat(4) { i ->
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = if (current.length > i) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                            modifier = Modifier.size(18.dp)
                        ) {}
                    }
                }
                if (error.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.height(16.dp))
                NumberPad(
                    onDigit = { d ->
                        error = ""
                        if (step == 1) {
                            if (firstPin.length < 4) {
                                firstPin += d
                                if (firstPin.length == 4) step = 2
                            }
                        } else {
                            if (secondPin.length < 4) {
                                secondPin += d
                                if (secondPin.length == 4) {
                                    if (firstPin == secondPin) onSave(firstPin)
                                    else { error = "PINs don't match"; firstPin = ""; secondPin = ""; step = 1 }
                                }
                            }
                        }
                    },
                    onDelete = {
                        error = ""
                        if (step == 2) { if (secondPin.isEmpty()) step = 1 else secondPin = secondPin.dropLast(1) }
                        else if (firstPin.isNotEmpty()) firstPin = firstPin.dropLast(1)
                    }
                )
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

// ---------------------------------------------------------------------------
// PIN unlock overlay  (SEC-02: reads/writes lockout state from ViewModel prefs)
// ---------------------------------------------------------------------------

@Composable
internal fun PinUnlockOverlay(
    lockedUntil: kotlinx.coroutines.flow.StateFlow<Long>,
    onDismiss: () -> Unit,
    onAttempt: (String) -> KioskUnlockResult,
) {
    val lockedUntilVal by lockedUntil.collectAsState()

    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var secondsRemaining by remember { mutableIntStateOf(0) }

    // Restart the countdown whenever a failed attempt establishes a new window.
    // Keying this effect to Unit would retain the pre-attempt timestamp and
    // overwrite the new countdown with stale state.
    LaunchedEffect(lockedUntilVal) {
        while (true) {
            val remainingMillis = lockedUntilVal - System.currentTimeMillis()
            val remainingSeconds = remainingMillis / 1_000L +
                if (remainingMillis > 0 && remainingMillis % 1_000L != 0L) 1L else 0L
            secondsRemaining = remainingSeconds.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
            if (remainingMillis <= 0) break
            kotlinx.coroutines.delay(1_000)
        }
    }

    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.78f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(32.dp),
            modifier = Modifier.padding(48.dp)
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.Lock,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(56.dp)
                )
                Spacer(Modifier.height(8.dp))
                Text("Admin Access", style = MaterialTheme.typography.headlineLarge, color = Color.White)
                val isLockedOut = System.currentTimeMillis() < lockedUntilVal
                Text(
                    if (isLockedOut) "Too many attempts" else "Enter PIN to unlock",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.7f)
                )
            }

            val isLockedOut = System.currentTimeMillis() < lockedUntilVal
            if (isLockedOut) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "Try again in ${secondsRemaining}s",
                        style = MaterialTheme.typography.titleLarge,
                        color = Color(0xFFFF9500)
                    )
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = onDismiss) { Text("Cancel", color = Color.White.copy(alpha = 0.7f)) }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    repeat(4) { i ->
                        Surface(
                            shape = MaterialTheme.shapes.extraSmall,
                            color = if (entered.length > i) Color.White else Color.White.copy(alpha = 0.3f),
                            modifier = Modifier.size(18.dp)
                        ) {}
                    }
                }
                if (error.isNotEmpty()) {
                    Text(error, color = Color(0xFFFF3B30), style = MaterialTheme.typography.bodySmall)
                }
                NumberPad(
                    tint = Color.White,
                    leadingButton = {
                        TextButton(onClick = onDismiss) {
                            Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                        }
                    },
                    onDigit = { d ->
                        if (System.currentTimeMillis() >= lockedUntilVal && entered.length < 4) {
                            error = ""
                            entered += d
                            if (entered.length == 4) {
                                when (val result = onAttempt(entered)) {
                                    KioskUnlockResult.Unlocked -> onDismiss()
                                    is KioskUnlockResult.IncorrectPin -> {
                                        val left = result.attemptsRemaining
                                        error =
                                            "Incorrect PIN — $left attempt${if (left == 1) "" else "s"} left"
                                        entered = ""
                                    }
                                    is KioskUnlockResult.LockedOut -> {
                                        error = ""
                                        entered = ""
                                    }
                                    KioskUnlockResult.NotConfigured -> {
                                        error = "No kiosk PIN is configured"
                                        entered = ""
                                    }
                                }
                            }
                        }
                    },
                    onDelete = { if (entered.isNotEmpty()) entered = entered.dropLast(1) }
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Number pad
// ---------------------------------------------------------------------------

@Composable
internal fun NumberPad(
    tint: Color = MaterialTheme.colorScheme.primary,
    leadingButton: (@Composable () -> Unit)? = null,
    onDigit: (String) -> Unit,
    onDelete: () -> Unit
) {
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { digit ->
                    NumKey(digit, tint) { onDigit(digit) }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (leadingButton != null) {
                Box(modifier = Modifier.size(72.dp), contentAlignment = Alignment.Center) {
                    leadingButton()
                }
            } else {
                Spacer(Modifier.size(72.dp))
            }
            NumKey("0", tint) { onDigit("0") }
            TextButton(onClick = onDelete, modifier = Modifier.size(72.dp)) {
                Text("⌫", style = MaterialTheme.typography.titleLarge, color = tint)
            }
        }
    }
}

@Composable
internal fun NumKey(digit: String, tint: Color, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = MaterialTheme.shapes.extraLarge,
        color = tint.copy(alpha = 0.15f),
        modifier = Modifier.size(72.dp)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(digit, style = MaterialTheme.typography.headlineMedium, color = tint)
        }
    }
}

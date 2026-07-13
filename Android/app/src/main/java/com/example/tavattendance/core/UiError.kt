package com.example.tavattendance.core

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * Maps a caught Throwable to a user-facing message: a human prefix plus the exception's own
 * message, falling back to its class name when the message is null. This is the string idiom the
 * roster/kiosk/session screens already build inline; centralised here so it is testable and every
 * screen reads the same. Pure — unit-tested in UiErrorTest.
 */
fun Throwable.asUserMessage(prefix: String): String =
    "$prefix: ${localizedMessage ?: javaClass.simpleName}"

/**
 * Full-screen "load failed" state with a Retry button — the shared version of the box that the
 * kiosk / roster / session screens render inline. Distinguishes a failed load from a genuinely
 * empty result so the empty state never lies about a fetch that actually threw.
 */
@Composable
fun ErrorRetry(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(message, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        Button(onClick = onRetry) { Text("Retry") }
    }
}

/**
 * Remembers a SnackbarHostState and shows [message] whenever it becomes non-null, then calls
 * [onShown] so the ViewModel can clear it. Pass the returned host to `Scaffold(snackbarHost = …)`.
 * Reusable surface for write failures that shouldn't replace on-screen content.
 */
@Composable
fun rememberSnackbarError(message: String?, onShown: () -> Unit): SnackbarHostState {
    val host = remember { SnackbarHostState() }
    LaunchedEffect(message) {
        message?.let {
            host.showSnackbar(it, duration = SnackbarDuration.Short)
            onShown()
        }
    }
    return host
}

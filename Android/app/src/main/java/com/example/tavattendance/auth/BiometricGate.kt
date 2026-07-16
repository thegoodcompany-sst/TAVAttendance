package com.example.tavattendance.auth

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

object BiometricPrefs {
    private const val KEY = "biometric_unlock"

    private fun prefs(context: Context) =
        context.getSharedPreferences("biometric", Context.MODE_PRIVATE)

    fun isEnabled(context: Context) = prefs(context).getBoolean(KEY, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY, enabled).apply()
    }

    fun isAvailable(context: Context) =
        BiometricManager.from(context)
            .canAuthenticate(BIOMETRIC_STRONG or DEVICE_CREDENTIAL) ==
            BiometricManager.BIOMETRIC_SUCCESS
}

fun showBiometricPrompt(
    activity: FragmentActivity,
    title: String,
    onSuccess: () -> Unit,
) {
    val prompt = BiometricPrompt(
        activity,
        ContextCompat.getMainExecutor(activity),
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onSuccess()
            }
        }
    )
    val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle(title)
        .setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
        .build()
    prompt.authenticate(info)
}

/**
 * Top-bar action toggling biometric unlock, shown only when biometrics are
 * available. Enabling runs one prompt first to confirm it works.
 */
@Composable
fun BiometricToggleAction() {
    val context = LocalContext.current
    if (!BiometricPrefs.isAvailable(context)) return
    var enabled by rememberSaveable { mutableStateOf(BiometricPrefs.isEnabled(context)) }
    TextButton(onClick = {
        if (enabled) {
            BiometricPrefs.setEnabled(context, false)
            enabled = false
        } else {
            showBiometricPrompt(context as FragmentActivity, "Enable biometric unlock") {
                BiometricPrefs.setEnabled(context, true)
                enabled = true
            }
        }
    }) {
        Text(if (enabled) "Biometric ✓" else "Biometric")
    }
}

/**
 * Biometric gate over the already-persisted Supabase session (opt-in via
 * [BiometricPrefs]). Mirrors iOS BiometricLockView: unlock with biometrics or
 * device credential, or sign out back to the password login.
 */
@Composable
fun BiometricGate(onSignOut: () -> Unit, content: @Composable () -> Unit) {
    val context = LocalContext.current
    var unlocked by rememberSaveable { mutableStateOf(false) }

    if (!BiometricPrefs.isEnabled(context)) {
        content()
        return
    }

    // ponytail: relocks on every stop incl. brief app switches; add a grace timer if users complain.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) unlocked = false
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    if (unlocked) {
        content()
        return
    }

    val activity = context as FragmentActivity
    LaunchedEffect(Unit) {
        showBiometricPrompt(activity, "Unlock TAVA Attendance") { unlocked = true }
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text("TAVA Attendance", style = MaterialTheme.typography.headlineSmall)
            Button(onClick = {
                showBiometricPrompt(activity, "Unlock TAVA Attendance") { unlocked = true }
            }) {
                Text("Unlock")
            }
            TextButton(onClick = onSignOut) { Text("Sign Out") }
        }
    }
}

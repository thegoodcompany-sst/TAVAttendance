package com.example.tavattendance.push

import com.example.tavattendance.core.SafeLog
import com.example.tavattendance.data.service.AttendanceService
import com.example.tavattendance.data.service.FeatureFlags
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Upserts this device's FCM token into `device_tokens` (migration 014) so the
 * notify-parent edge function can reach it. Gated on the `push_notifications`
 * flag — with the flag OFF this is a no-op, so the feature ships dark.
 */
object PushTokenRegistrar {

    /** Call after sign-in (flags loaded) and on token refresh. Best-effort. */
    suspend fun registerIfEnabled() {
        if (!FeatureFlags.isEnabled(FeatureFlags.PUSH_NOTIFICATIONS)) return
        runCatching {
            AttendanceService.registerDeviceToken(currentToken(), platform = "android")
        }.onFailure { SafeLog.warning("PushTokenRegistrar", "token registration failed", it) }
    }

    private suspend fun currentToken(): String =
        suspendCancellableCoroutine { cont ->
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { cont.resumeWithException(it) }
        }
}

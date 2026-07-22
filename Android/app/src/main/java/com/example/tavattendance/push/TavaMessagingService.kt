package com.example.tavattendance.push

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import com.example.tavattendance.MainActivity
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Shows pushes from the notify-parent edge function (flag `push_notifications`).
 * Tapping opens MainActivity; a parent lands on the dashboard, where the
 * safely-home card for an unconfirmed dismissal is shown.
 */
class TavaMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        // Fired on install/restore/rotation. Re-upsert if the feature is live
        // (no-op when signed out — registerDeviceToken returns without a user).
        CoroutineScope(Dispatchers.IO).launch { PushTokenRegistrar.registerIfEnabled() }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // Never render server-supplied text on the lock screen. Notification payloads can
        // contain personal attendance data if a sender is misconfigured or compromised.
        val title = NOTIFICATION_TITLE
        val body = NOTIFICATION_BODY

        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,
            "Attendance alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })

        val tapIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val publicVersion = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(NOTIFICATION_TITLE)
            .setContentText(PUBLIC_NOTIFICATION_BODY)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .setAutoCancel(true)
            .setContentIntent(tapIntent)
            .build()

        // dismissal_id (when present) keeps one notification per dismissal event.
        manager.notify(message.data["dismissal_id"]?.hashCode() ?: body.hashCode(), notification)
    }

    private companion object {
        const val CHANNEL_ID = "attendance_alerts"
        const val NOTIFICATION_TITLE = "TAVA Attendance"
        const val NOTIFICATION_BODY = "You have a new attendance update."
        const val PUBLIC_NOTIFICATION_BODY = "Open TAVA Attendance to view this update."
    }
}

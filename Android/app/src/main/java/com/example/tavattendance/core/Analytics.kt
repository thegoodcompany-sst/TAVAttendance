package com.example.tavattendance.core

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import com.example.tavattendance.data.service.FeatureFlags
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.UUID

/** Event type — mirrors the `app_events.event_type` CHECK (migration 031). */
enum class AnalyticsEventType(val raw: String) {
    SCREEN_VIEW("screen_view"), TAP("tap"), ERROR("error"),
    CRASH("crash"), OPS("ops"), LATENCY("latency")
}

/**
 * One `app_events` row. `properties` carries IDs/counts only — NEVER student
 * names (PDPA). Context fields (user/role/version/platform/device/session) are
 * stamped by [Analytics] at build time.
 */
@Serializable
data class AppEvent(
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("user_id") val userId: String?,
    val role: String?,
    val platform: String,
    @SerialName("app_version") val appVersion: String?,
    @SerialName("session_id") val sessionId: String,
    @SerialName("event_type") val eventType: String,
    val name: String,
    val properties: JsonObject,
    val device: String?
)

/**
 * Supabase-native, fail-silent product analytics + observability (migration 031).
 * Mirror of iOS `Services/Analytics.swift`.
 *
 * - No-op unless the `analytics` feature flag is ON (loaded once at sign-in;
 *   pre-flag events are dropped — acceptable).
 * - In-memory batch, flushed every 30s and when the app backgrounds.
 * - **Drop on failure**: a failed insert discards the batch. There is
 *   deliberately no second offline queue — attendance capture must never be
 *   blocked or complicated by analytics.
 */
object Analytics {
    private const val PLATFORM = "android"
    internal const val MAX_BUFFERED = 500
    private val EMPTY = JsonObject(emptyMap())

    private val lock = Any()
    /** Buffered events awaiting the next flush. Internal for tests. */
    internal val buffer = mutableListOf<AppEvent>()
    private val sessionId = UUID.randomUUID().toString()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Set from `AuthViewModel` after the session/profile resolve. */
    var userId: String? = null
    var role: String? = null
    private var appVersion: String? = null
    private var device: String? = null
    private var started = false

    private val enabled: Boolean get() = FeatureFlags.isEnabled(FeatureFlags.ANALYTICS)

    // MARK: lifecycle

    /**
     * Stamps device/version context, checks for a crash since last launch, starts
     * the 30s flush loop and emits `app_launch`. Call once after flags load.
     */
    fun start(context: Context) {
        if (started) return
        started = true
        appVersion = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull()
        device = Build.MODEL
        checkForCrash(context)
        scope.launch {
            while (isActive) {
                delay(30_000)
                flush()
            }
        }
        track(AnalyticsEventType.OPS, "app_launch", buildJsonObject { put("cold", true) })
    }

    // MARK: capture

    /** Public entry point — no-op while the flag is OFF. */
    fun track(type: AnalyticsEventType, name: String, properties: JsonObject = EMPTY) {
        if (!enabled) return
        record(type, name, properties)
    }

    /** Buffers unconditionally (no flag gate). The seam used by [track] and tests. */
    internal fun record(type: AnalyticsEventType, name: String, properties: JsonObject = EMPTY) {
        val event = AppEvent(
            occurredAt = Instant.now().toString(),
            userId = userId,
            role = role,
            platform = PLATFORM,
            appVersion = appVersion,
            sessionId = sessionId,
            eventType = type.raw,
            name = name,
            properties = properties,
            device = device
        )
        synchronized(lock) {
            buffer.add(event)
            // Long offline stretches must not grow the buffer without bound; shed oldest.
            if (buffer.size > MAX_BUFFERED) {
                repeat(buffer.size - MAX_BUFFERED) { buffer.removeAt(0) }
            }
        }
    }

    /** Handled-error funnel. `screen`/`message` are technical strings — never student names. */
    fun trackError(screen: String, error: Throwable) {
        track(AnalyticsEventType.ERROR, "handled_error", buildJsonObject {
            put("message", error.message ?: error.javaClass.simpleName)
            put("screen", screen)
        })
    }

    /** Fire-and-forget flush (app background / onStop). */
    fun flushNow() { scope.launch { flush() } }

    // MARK: flush

    /**
     * Sends the buffered batch, **dropping it on any failure** — the buffer is
     * cleared before the send, so a throwing [sink] simply discards those events.
     * [sink] is injectable for tests; production uses the Supabase insert.
     */
    internal suspend fun flush(sink: suspend (List<AppEvent>) -> Unit) {
        val batch: List<AppEvent>
        synchronized(lock) {
            if (buffer.isEmpty()) return
            batch = buffer.toList()
            buffer.clear()
        }
        runCatching { sink(batch) }
    }

    suspend fun flush() = flush { batch ->
        SupabaseClient.client.from("app_events").insert(batch)
    }

    // MARK: crash diagnostics (next-launch detection)

    private fun checkForCrash(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        runCatching {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val prefs = context.getSharedPreferences("analytics", Context.MODE_PRIVATE)
            val watermark = prefs.getLong("crash_watermark", 0L)
            var newest = watermark
            for (info in am.getHistoricalProcessExitReasons(null, 0, 20)) {
                if (info.timestamp <= watermark) continue
                newest = maxOf(newest, info.timestamp)
                val mechanism = when (info.reason) {
                    ApplicationExitInfo.REASON_CRASH -> "crash"
                    ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
                    ApplicationExitInfo.REASON_ANR -> "anr"
                    else -> continue
                }
                track(AnalyticsEventType.CRASH, "crash_detected", buildJsonObject {
                    put("mechanism", mechanism)
                    put("reason", info.description ?: "unknown")
                })
            }
            prefs.edit().putLong("crash_watermark", newest).apply()
        }
    }
}

/** One line per staff screen — emits a `screen_view` on first composition. */
@Composable
fun TrackScreen(name: String) {
    LaunchedEffect(Unit) { Analytics.track(AnalyticsEventType.SCREEN_VIEW, name) }
}

package com.example.tavattendance.core

import android.util.Log
import com.example.tavattendance.BuildConfig

/**
 * Debug-only diagnostics that never include exception messages or stack traces.
 *
 * Supabase errors can contain identifiers and response bodies, so production builds must not
 * forward them to logcat. Callers should pass a static event name rather than user data.
 */
object SafeLog {
    fun error(tag: String, event: String, cause: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            Log.e(tag, diagnostic(event, cause))
        }
    }

    fun warning(tag: String, event: String, cause: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            Log.w(tag, diagnostic(event, cause))
        }
    }

    private fun diagnostic(event: String, cause: Throwable?): String =
        cause?.let { "$event (${it.javaClass.simpleName})" } ?: event
}

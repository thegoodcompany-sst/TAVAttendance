package com.example.tavattendance.core

import android.content.Context
import com.example.tavattendance.BuildConfig
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage

object SupabaseClient {
    @Volatile
    private var applicationContext: Context? = null

    fun initialize(context: Context) {
        applicationContext = context.applicationContext
    }

    val client by lazy {
        val context = checkNotNull(applicationContext) {
            "SupabaseClient must be initialized from TavaApplication"
        }
        val secureStore = KeystoreStringStore(context)
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_PROJECT_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY
        ) {
            install(Auth) {
                sessionManager = EncryptedSessionManager(
                    context = context,
                    supabaseUrl = BuildConfig.SUPABASE_PROJECT_URL,
                    store = secureStore,
                )
                codeVerifierCache = EncryptedCodeVerifierCache(
                    context = context,
                    supabaseUrl = BuildConfig.SUPABASE_PROJECT_URL,
                    store = secureStore,
                )
            }
            install(Postgrest)
            install(Storage)
        }
    }
}

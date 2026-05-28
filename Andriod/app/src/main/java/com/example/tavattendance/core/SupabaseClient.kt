package com.example.tavattendance.core

import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.postgrest.Postgrest

object SupabaseClient {
    val client = createSupabaseClient(
        supabaseUrl = SupabaseConfig.PROJECT_URL,
        supabaseKey = SupabaseConfig.ANON_KEY
    ) {
        install(Auth)
        install(Postgrest)
    }
}

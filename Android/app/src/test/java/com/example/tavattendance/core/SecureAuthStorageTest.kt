package com.example.tavattendance.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SecureAuthStorageTest {
    @Test
    fun legacySettingsKeyMatchesSupabaseKtDefault() {
        assertEquals(
            "sb-https:--example-supabase-co-session",
            legacySupabaseSettingsKey("https://example.supabase.co", "session"),
        )
        assertEquals(
            "sb-https:--example-supabase-co-supabase_code_verifier",
            legacySupabaseSettingsKey(
                "https://example.supabase.co/",
                "supabase_code_verifier",
            ),
        )
    }
}

package com.example.tavattendance

import android.app.Application
import com.example.tavattendance.core.SupabaseClient

class TavaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        SupabaseClient.initialize(this)
    }
}

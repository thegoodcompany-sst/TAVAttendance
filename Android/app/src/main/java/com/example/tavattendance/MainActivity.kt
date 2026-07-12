package com.example.tavattendance

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.auth.AuthViewModel
import com.example.tavattendance.auth.LoginScreen
import com.example.tavattendance.navigation.AdminApp
import com.example.tavattendance.navigation.TutorApp
import com.example.tavattendance.screens.ParentDashboardScreen
import com.example.tavattendance.ui.theme.TAVAttendanceTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // PDPA export files (contain a student UUID in the filename) are written to
        // cacheDir/exports for the share intent and otherwise never cleaned up. Wipe them
        // on every cold start — simplest reliable point since we don't get a share-intent
        // completion callback.
        java.io.File(cacheDir, "exports").deleteRecursively()
        enableEdgeToEdge()
        setContent {
            TAVAttendanceTheme {
                val authViewModel: AuthViewModel = viewModel()
                val isLoading by authViewModel.isLoading.collectAsState()
                val isAuthenticated by authViewModel.isAuthenticated.collectAsState()
                val profile by authViewModel.currentProfile.collectAsState()
                val profileError by authViewModel.profileError.collectAsState()

                when {
                    isLoading -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                    !isAuthenticated -> LoginScreen(authViewModel = authViewModel)
                    // Profile fetch failed: do NOT fall through to the tutor UI (an admin whose
                    // profile fetch failed would silently lose admin capabilities).
                    profile == null && profileError != null -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.padding(16.dp)
                        ) {
                            Text(profileError ?: "Failed to load profile", color = MaterialTheme.colorScheme.error)
                            Button(onClick = { authViewModel.retryFetchProfile() }) { Text("Retry") }
                        }
                    }
                    profile == null -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                    profile?.role == "admin" -> AdminApp(authViewModel = authViewModel)
                    profile?.role == "parent" -> ParentDashboardScreen(authViewModel = authViewModel)
                    else -> TutorApp(authViewModel = authViewModel)
                }
            }
        }
    }
}

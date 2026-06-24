package com.example.tavattendance

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.tavattendance.auth.AuthViewModel
import com.example.tavattendance.auth.LoginScreen
import com.example.tavattendance.navigation.AdminApp
import com.example.tavattendance.navigation.TutorApp
import com.example.tavattendance.ui.theme.TAVAttendanceTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TAVAttendanceTheme {
                val authViewModel: AuthViewModel = viewModel()
                val isLoading by authViewModel.isLoading.collectAsState()
                val isAuthenticated by authViewModel.isAuthenticated.collectAsState()
                val profile by authViewModel.currentProfile.collectAsState()

                when {
                    isLoading -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                    !isAuthenticated -> LoginScreen(authViewModel = authViewModel)
                    profile?.role == "admin" -> AdminApp(authViewModel = authViewModel)
                    else -> TutorApp(authViewModel = authViewModel)
                }
            }
        }
    }
}

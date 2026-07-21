package com.example.tavattendance.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.AccountBox
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.tavattendance.auth.AuthViewModel
import com.example.tavattendance.screens.*
import com.example.tavattendance.screens.kiosk.GlobalKioskScreen

sealed class Screen(val route: String) {
    object Classes : Screen("classes")
    object Students : Screen("students")
    object Kiosk : Screen("kiosk")
    object Sessions : Screen("sessions/{classId}/{className}") {
        fun createRoute(classId: String, className: String) =
            "sessions/${encode(classId)}/${encode(className)}"
    }
    object Roster : Screen("roster/{sessionId}/{sessionDate}/{classId}/{className}") {
        fun createRoute(sessionId: String, sessionDate: String, classId: String, className: String) =
            "roster/${encode(sessionId)}/${encode(sessionDate)}/${encode(classId)}/${encode(className)}"
    }
    object AddPastSession : Screen("past_session/{classId}/{className}") {
        fun createRoute(classId: String, className: String) =
            "past_session/${encode(classId)}/${encode(className)}"
    }
    object HistoricalSession : Screen("historical_session/{sessionId}/{classId}/{className}") {
        fun createRoute(sessionId: String, classId: String, className: String) =
            "historical_session/${encode(sessionId)}/${encode(classId)}/${encode(className)}"
    }
    object Enrollment : Screen("enrollment/{classId}/{className}") {
        fun createRoute(classId: String, className: String) =
            "enrollment/${encode(classId)}/${encode(className)}"
    }
    object TutorAssignment : Screen("tutor_assignment/{classId}/{className}") {
        fun createRoute(classId: String, className: String) =
            "tutor_assignment/${encode(classId)}/${encode(className)}"
    }
}

private fun encode(s: String) = java.net.URLEncoder.encode(s, "UTF-8")
private fun decode(s: String) = java.net.URLDecoder.decode(s, "UTF-8")

@Composable
fun AdminApp(authViewModel: AuthViewModel) {
    val navController = rememberNavController()
    val navBackStack by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStack?.destination?.route

    val topLevelRoutes = listOf(Screen.Classes.route, Screen.Students.route, Screen.Kiosk.route)
    val showBottomBar = currentRoute in topLevelRoutes

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    NavigationBarItem(
                        selected = currentRoute == Screen.Classes.route,
                        onClick = {
                            navController.navigate(Screen.Classes.route) {
                                popUpTo(Screen.Classes.route) { inclusive = true }
                            }
                        },
                        icon = { Icon(Icons.Default.List, contentDescription = null) },
                        label = { Text("Classes") }
                    )
                    NavigationBarItem(
                        selected = currentRoute == Screen.Students.route,
                        onClick = {
                            navController.navigate(Screen.Students.route) {
                                popUpTo(Screen.Classes.route)
                            }
                        },
                        icon = { Icon(Icons.Default.Person, contentDescription = null) },
                        label = { Text("Students") }
                    )
                    NavigationBarItem(
                        selected = currentRoute == Screen.Kiosk.route,
                        onClick = {
                            navController.navigate(Screen.Kiosk.route) {
                                popUpTo(Screen.Classes.route)
                            }
                        },
                        icon = { Icon(Icons.Default.AccountBox, contentDescription = null) },
                        label = { Text("Sign In") }
                    )
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            AppNavHost(navController = navController, authViewModel = authViewModel, isAdmin = true)
        }
    }
}

@Composable
fun TutorApp(authViewModel: AuthViewModel) {
    val navController = rememberNavController()
    val navBackStack by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStack?.destination?.route

    val topLevelRoutes = listOf(Screen.Classes.route, Screen.Students.route)
    val showBottomBar = currentRoute in topLevelRoutes

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    NavigationBarItem(
                        selected = currentRoute == Screen.Classes.route,
                        onClick = {
                            navController.navigate(Screen.Classes.route) {
                                popUpTo(Screen.Classes.route) { inclusive = true }
                            }
                        },
                        icon = { Icon(Icons.Default.List, contentDescription = null) },
                        label = { Text("Classes") }
                    )
                    NavigationBarItem(
                        selected = currentRoute == Screen.Students.route,
                        onClick = {
                            navController.navigate(Screen.Students.route) {
                                popUpTo(Screen.Classes.route)
                            }
                        },
                        icon = { Icon(Icons.Default.Person, contentDescription = null) },
                        label = { Text("Students") }
                    )
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            AppNavHost(navController = navController, authViewModel = authViewModel, isAdmin = false)
        }
    }
}

@Composable
fun AppNavHost(
    navController: NavHostController,
    authViewModel: AuthViewModel,
    isAdmin: Boolean
) {
    NavHost(navController = navController, startDestination = Screen.Classes.route) {
        composable(Screen.Classes.route) {
            ClassListScreen(
                authViewModel = authViewModel,
                isAdmin = isAdmin,
                onClassClick = { cls ->
                    navController.navigate(Screen.Sessions.createRoute(cls.id, cls.name))
                },
                onSignOut = { authViewModel.signOut() }
            )
        }

        composable(
            route = Screen.Sessions.route,
            arguments = listOf(
                navArgument("classId") { type = NavType.StringType },
                navArgument("className") { type = NavType.StringType }
            )
        ) { backStack ->
            val classId = decode(backStack.arguments?.getString("classId") ?: "")
            val className = decode(backStack.arguments?.getString("className") ?: "")
            SessionListScreen(
                classId = classId,
                className = className,
                isAdmin = isAdmin,
                onSessionClick = { session ->
                    navController.navigate(
                        Screen.Roster.createRoute(session.id, session.sessionDate, classId, className)
                    )
                },
                onHistoricalSessionClick = { session ->
                    navController.navigate(
                        Screen.HistoricalSession.createRoute(session.id, classId, className)
                    )
                },
                onAddPastSession = {
                    navController.navigate(Screen.AddPastSession.createRoute(classId, className))
                },
                onManageEnrollment = {
                    navController.navigate(Screen.Enrollment.createRoute(classId, className))
                },
                onManageTutors = {
                    navController.navigate(Screen.TutorAssignment.createRoute(classId, className))
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.AddPastSession.route,
            arguments = listOf(
                navArgument("classId") { type = NavType.StringType },
                navArgument("className") { type = NavType.StringType }
            )
        ) { backStack ->
            val classId = decode(backStack.arguments?.getString("classId") ?: "")
            val className = decode(backStack.arguments?.getString("className") ?: "")
            PastSessionScreen(
                classId = classId,
                className = className,
                onBack = { navController.popBackStack() },
                onCreated = { session ->
                    navController.popBackStack()
                    navController.navigate(
                        Screen.HistoricalSession.createRoute(session.id, classId, className)
                    )
                },
                onExisting = { session ->
                    navController.popBackStack()
                    navController.navigate(
                        Screen.HistoricalSession.createRoute(session.id, classId, className)
                    )
                }
            )
        }

        composable(
            route = Screen.HistoricalSession.route,
            arguments = listOf(
                navArgument("sessionId") { type = NavType.StringType },
                navArgument("classId") { type = NavType.StringType },
                navArgument("className") { type = NavType.StringType }
            )
        ) { backStack ->
            HistoricalSessionScreen(
                sessionId = decode(backStack.arguments?.getString("sessionId") ?: ""),
                classId = decode(backStack.arguments?.getString("classId") ?: ""),
                className = decode(backStack.arguments?.getString("className") ?: ""),
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.Roster.route,
            arguments = listOf(
                navArgument("sessionId") { type = NavType.StringType },
                navArgument("sessionDate") { type = NavType.StringType },
                navArgument("classId") { type = NavType.StringType },
                navArgument("className") { type = NavType.StringType }
            )
        ) { backStack ->
            val sessionId = decode(backStack.arguments?.getString("sessionId") ?: "")
            val sessionDate = decode(backStack.arguments?.getString("sessionDate") ?: "")
            val classId = decode(backStack.arguments?.getString("classId") ?: "")
            val className = decode(backStack.arguments?.getString("className") ?: "")
            RosterScreen(
                sessionId = sessionId,
                sessionDate = sessionDate,
                className = className,
                onBack = { navController.popBackStack() }
            )
        }

        composable(Screen.Students.route) {
            // Admins manage the roster; tutors enter grades for their assigned classes.
            if (isAdmin) StudentManagementScreen() else StudentResultsScreen()
        }

        if (isAdmin) {
            composable(Screen.Kiosk.route) {
                GlobalKioskScreen()
            }

            composable(
                route = Screen.Enrollment.route,
                arguments = listOf(
                    navArgument("classId") { type = NavType.StringType },
                    navArgument("className") { type = NavType.StringType }
                )
            ) { backStack ->
                val classId = decode(backStack.arguments?.getString("classId") ?: "")
                val className = decode(backStack.arguments?.getString("className") ?: "")
                EnrollmentScreen(
                    classId = classId,
                    className = className,
                    onBack = { navController.popBackStack() }
                )
            }

            composable(
                route = Screen.TutorAssignment.route,
                arguments = listOf(
                    navArgument("classId") { type = NavType.StringType },
                    navArgument("className") { type = NavType.StringType }
                )
            ) { backStack ->
                val classId = decode(backStack.arguments?.getString("classId") ?: "")
                val className = decode(backStack.arguments?.getString("className") ?: "")
                TutorAssignmentScreen(
                    classId = classId,
                    className = className,
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}

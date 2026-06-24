import AppIntents

/// Surfaces the app's intents to Siri, Spotlight, and the Shortcuts app with natural-language
/// trigger phrases. Every phrase must include `\(.applicationName)` so Siri can scope it to
/// this app.
struct TAVAShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SignInStudentIntent(),
            phrases: [
                "Sign in \(\.$student) with \(.applicationName)",
                "Sign \(\.$student) in with \(.applicationName)",
                "Check in \(\.$student) with \(.applicationName)",
            ],
            shortTitle: "Sign In Student",
            systemImageName: "person.fill.checkmark")

        AppShortcut(
            intent: MarkAttendanceIntent(),
            phrases: [
                // App Shortcut phrases allow at most one parameter each; Siri prompts
                // for the status after resolving the student.
                "Mark \(\.$student)'s attendance in \(.applicationName)",
                "Set \(\.$student)'s attendance in \(.applicationName)",
                "Mark attendance with \(.applicationName)",
            ],
            shortTitle: "Mark Attendance",
            systemImageName: "checklist")

        AppShortcut(
            intent: CheckStudentStatusIntent(),
            phrases: [
                "Is \(\.$student) here today in \(.applicationName)",
                "Check \(\.$student)'s status in \(.applicationName)",
                "Has \(\.$student) signed in with \(.applicationName)",
            ],
            shortTitle: "Check Student Status",
            systemImageName: "questionmark.circle")

        AppShortcut(
            intent: TodayAttendanceSummaryIntent(),
            phrases: [
                "How many students have signed in with \(.applicationName)",
                "Today's attendance summary in \(.applicationName)",
                "Attendance count in \(.applicationName)",
            ],
            shortTitle: "Today's Summary",
            systemImageName: "person.3.fill")

        AppShortcut(
            intent: StudentAttendanceRateIntent(),
            phrases: [
                "What's \(\.$student)'s attendance rate in \(.applicationName)",
                "Attendance rate for \(\.$student) in \(.applicationName)",
            ],
            shortTitle: "Attendance Rate",
            systemImageName: "chart.bar.fill")

        AppShortcut(
            intent: ClassPunctualityIntent(),
            phrases: [
                "How punctual is \(\.$targetClass) in \(.applicationName)",
                "Punctuality for \(\.$targetClass) in \(.applicationName)",
            ],
            shortTitle: "Class Punctuality",
            systemImageName: "clock.fill")

        AppShortcut(
            intent: OpenKioskIntent(),
            phrases: [
                "Open the sign-in kiosk in \(.applicationName)",
                "Open the kiosk in \(.applicationName)",
                "Show the sign-in screen in \(.applicationName)",
            ],
            shortTitle: "Open Kiosk",
            systemImageName: "person.wave.2.fill")
    }
}

import Foundation
import AppIntents

/// "Open the sign-in kiosk" — launches the app and switches to the Sign-In tab.
struct OpenKioskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sign-In Kiosk"
    static var description = IntentDescription("Opens TAVAttendance on the Sign-In kiosk tab.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        KioskRouter.shared.selectedTab = .signIn
        return .result()
    }
}

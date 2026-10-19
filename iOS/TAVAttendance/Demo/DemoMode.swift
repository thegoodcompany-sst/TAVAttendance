import Foundation

/// On-device demo mode.
///
/// Signing in as `demo@thegoodcompanysg.dev` never talks to Supabase. The app
/// switches every `AttendanceService` read and write to `DemoStore`, a seeded
/// in-memory dataset that lives only on this device. Nothing is persisted to the
/// production database, and `DemoNetworkGuard` refuses any Supabase request that
/// slips past the service seam while demo mode is active.
///
/// Signing out (or tapping "Reset demo") throws the demo data away and reseeds it.
enum DemoMode {
    /// The one email address that enters demo mode (compared case-insensitively).
    static let demoEmail = "demo@thegoodcompanysg.dev"

    /// Stable identity of the local demo admin. Never exists in Supabase.
    static let userId = UUID(uuidString: "de000001-0000-4000-8000-000000000001")!

    static let profile = Profile(id: userId, fullName: "Demo Admin", role: "admin", phone: nil)

    /// Flags the demo turns on so every screen has something to show. Push,
    /// analytics, and photo uploads stay OFF because they would need a backend.
    static let featureFlags: [String: Bool] = [
        FeatureFlag.parentPortal.rawValue: true,
        FeatureFlag.studySpaceTracking.rawValue: true,
        // test_mode lets the kiosk show every class on any day, so a rehearsal on
        // a non-tuition day still has a full sign-in board.
        FeatureFlag.testMode.rawValue: true,
        FeatureFlag.sessionNotes.rawValue: true,
        FeatureFlag.qrSignIn.rawValue: true,
        FeatureFlag.retrospectiveSessions.rawValue: true,
        FeatureFlag.pushNotifications.rawValue: false,
        FeatureFlag.studentPhotos.rawValue: false,
        FeatureFlag.analytics.rawValue: false,
    ]

    private static let kioskDefaultsName = "tava.demo.kiosk"
    private static let demoKioskDefaults = UserDefaults(suiteName: kioskDefaultsName)!

    /// Demo PIN settings must never change the real kiosk's credentials or lockout.
    static var kioskDefaults: UserDefaults {
        isActive ? demoKioskDefaults : .standard
    }

    @MainActor
    static func resetKiosk() {
        demoKioskDefaults.removePersistentDomain(forName: kioskDefaultsName)
        demoKioskDefaults.set("0000", forKey: "kioskPIN")
        demoKioskDefaults.set(true, forKey: "kioskLocked")
        KioskSecurityState.shared.isAdminUnlocked = false
    }

    private static let lock = NSLock()
    private static var active = false
    private static let defaultsKey = "tava.demoMode.active"

    /// True while the app is running against the on-device demo store.
    static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    static func isDemoEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == demoEmail
    }

    /// Turns demo mode on or off. `persist` keeps the choice across relaunches
    /// (the demo data itself is always reseeded on launch).
    static func setActive(_ value: Bool, persist: Bool = true) {
        lock.lock()
        active = value
        lock.unlock()
        if persist {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        }
    }

    /// Whether the previous launch ended inside demo mode.
    static var wasActiveOnLastLaunch: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

enum DemoModeError: LocalizedError {
    case networkBlocked
    case notFound(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .networkBlocked:
            return String(localized: "Demo mode is offline by design. Nothing was sent to the server.")
        case .notFound(let what):
            return String(localized: "Demo data not found: \(what)")
        case .unavailable(let what):
            return what
        }
    }
}

/// Safety net under the service seam: every request made through the app's
/// Supabase client passes through this protocol first. While demo mode is
/// active it fails the request locally instead of letting it reach the network,
/// so a missed demo branch shows an error rather than touching production.
final class DemoNetworkGuard: URLProtocol {
    private static let counterLock = NSLock()
    private static var blocked = 0

    /// Number of requests refused since launch (used by tests).
    static var blockedRequestCount: Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return blocked
    }

    static func resetBlockedRequestCount() {
        counterLock.lock()
        blocked = 0
        counterLock.unlock()
    }

    #if DEBUG
    /// Test-only boundary: when set, requests made outside demo mode are also
    /// stopped here (and recorded) instead of reaching the network, so tests can
    /// prove the real Supabase path was taken without network access.
    private static var recordingOutsideDemo = false
    private static var recorded: [URL] = []

    static func startRecordingRealRequests() {
        counterLock.lock()
        recordingOutsideDemo = true
        recorded = []
        counterLock.unlock()
    }

    static func stopRecordingRealRequests() -> [URL] {
        counterLock.lock()
        defer { counterLock.unlock() }
        recordingOutsideDemo = false
        return recorded
    }

    private static var isRecordingOutsideDemo: Bool {
        counterLock.lock()
        defer { counterLock.unlock() }
        return recordingOutsideDemo
    }
    #endif

    override class func canInit(with request: URLRequest) -> Bool {
        #if DEBUG
        if isRecordingOutsideDemo { return true }
        #endif
        return DemoMode.isActive
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        #if DEBUG
        if !DemoMode.isActive && Self.isRecordingOutsideDemo {
            Self.counterLock.lock()
            if let url = request.url { Self.recorded.append(url) }
            Self.counterLock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        #endif
        Self.counterLock.lock()
        Self.blocked += 1
        Self.counterLock.unlock()
        client?.urlProtocol(self, didFailWithError: DemoModeError.networkBlocked)
    }

    override func stopLoading() {}

    /// URLSession used by the Supabase client: the demo guard runs before the
    /// system protocols on every request.
    static func guardedSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [DemoNetworkGuard.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }
}

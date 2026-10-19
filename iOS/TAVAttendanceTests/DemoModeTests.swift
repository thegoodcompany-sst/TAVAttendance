import XCTest
@testable import TAVAttendance

/// On-device demo mode: the demo email switches every read/write to the local
/// seeded store and nothing reaches Supabase.
final class DemoModeTests: XCTestCase {
    /// Monday 19 Oct 2026, 10:00 Singapore time.
    private let fixedNow = Date(timeIntervalSince1970: 1_792_375_200)

    override func setUp() {
        super.setUp()
        DemoMode.setActive(false, persist: false)
        DemoNetworkGuard.resetBlockedRequestCount()
    }

    override func tearDown() {
        DemoMode.setActive(false, persist: false)
        UserDefaults.standard.removeObject(forKey: "tava.demoMode.active")
        DemoStore.shared.reset()
        super.tearDown()
    }

    func testOnlyTheDemoEmailEntersDemoModeCaseInsensitively() {
        XCTAssertEqual(DemoMode.demoEmail, "demo@thegoodcompanysg.dev")
        XCTAssertTrue(DemoMode.isDemoEmail("demo@thegoodcompanysg.dev"))
        XCTAssertTrue(DemoMode.isDemoEmail("  Demo@TheGoodCompanySG.dev "))
        XCTAssertFalse(DemoMode.isDemoEmail("edmund@thegoodcompanysg.dev"))
        XCTAssertFalse(DemoMode.isDemoEmail("demo@thegoodcompany.dev"))
        XCTAssertFalse(DemoMode.isDemoEmail("demo@thegoodcompanysg.dev.example.com"))
        XCTAssertFalse(DemoMode.isDemoEmail(""))
    }

    @MainActor
    func testDemoKioskAcceptsAnyFourDigitsAndKeepsRealSettingsUntouched() {
        let keys = ["kioskPIN", "kioskLocked", "kioskFailedAttempts", "kioskLockoutUntil",
                    "kioskBiometricUnlock"]
        let realSettings = keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
        let realPIN = hashPIN("1234")
        DemoMode.setActive(true, persist: false)
        DemoMode.resetKiosk()

        XCTAssertTrue(DemoMode.kioskDefaults.bool(forKey: "kioskLocked"))
        for pin in ["0853", "9999", "0000", "1234"] {
            XCTAssertTrue(kioskPINMatches(entered: pin, storedPIN: realPIN))
            XCTAssertTrue(kioskPINMatches(entered: pin, storedPIN: ""))
        }
        for pin in ["", "085", "08530", "abcd"] {
            XCTAssertFalse(kioskPINMatches(entered: pin, storedPIN: realPIN))
        }
        DemoMode.kioskDefaults.set("changed-demo-pin", forKey: "kioskPIN")
        DemoMode.kioskDefaults.set(false, forKey: "kioskLocked")
        KioskSecurityState.shared.isAdminUnlocked = true
        DemoMode.setActive(false, persist: false)
        DemoMode.resetKiosk()

        XCTAssertFalse(KioskSecurityState.shared.isAdminUnlocked)
        XCTAssertEqual(keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }, realSettings)
        XCTAssertFalse(kioskPINMatches(entered: "0853", storedPIN: realPIN))
        XCTAssertFalse(kioskPINMatches(entered: "0853", storedPIN: ""))
        XCTAssertTrue(kioskPINMatches(entered: "1234", storedPIN: realPIN))
    }

    func testSeedIsSafeAndComplete() {
        let data = DemoSeed.make(now: fixedNow)
        XCTAssertEqual(data.students.count, 24)
        XCTAssertEqual(data.classes.filter { $0.isStudySpace != true }.count, 4)
        XCTAssertEqual(data.classes.filter { $0.isStudySpace == true }.map(\.id), [AttendanceService.studySpaceClassId])
        XCTAssertFalse(data.sessions.isEmpty)
        XCTAssertFalse(data.attendance.isEmpty)
        XCTAssertFalse(data.results.isEmpty)
        XCTAssertFalse(data.resultSlips.isEmpty)
        XCTAssertFalse(data.messages.isEmpty)
        XCTAssertFalse(data.corrections.isEmpty)
        XCTAssertEqual(data.consents.count, data.students.count)
        XCTAssertTrue(data.profiles.contains { $0.role == "tutor" })
        XCTAssertTrue(data.profiles.contains { $0.role == "parent" })

        for name in ["Lauren Tan", "Brian Chew", "Agrim Singh", "Nick Chan"] {
            XCTAssertNotNil(data.students.first { $0.fullName == name }, "\(name) should be on the demo roster")
        }

        // Three-valued status only, absence_informed only on absent rows.
        XCTAssertTrue(data.attendance.allSatisfy { $0.status != .absent ? $0.absenceInformed == nil : true })

        // Today has an open session for every regular class.
        let today = AttendanceService.ymdFormatter.string(from: fixedNow)
        let todaySessions = data.sessions.filter { $0.sessionDate == today }
        XCTAssertEqual(todaySessions.count, 4)
        XCTAssertTrue(todaySessions.allSatisfy { $0.endedAt == nil })

        // IDs are stable and match web/lib/demo/seed.ts.
        XCTAssertEqual(DemoSeed.id(.student, 1).uuidString.lowercased(), "de000003-0000-4000-8000-000000000001")
        XCTAssertEqual(data.students.first { $0.fullName == "Nick Chan" }?.id, DemoSeed.id(.student, 1))
        XCTAssertEqual(DemoSeed.make(now: fixedNow).students.map(\.id), data.students.map(\.id))
    }

    func testDemoReadsAndWritesStayOnDeviceAndResetRestoresTheSeed() async throws {
        DemoMode.setActive(true, persist: false)
        DemoStore.shared.reset()
        let service = AttendanceService.shared

        let classes = try await service.fetchMyClasses()
        XCTAssertEqual(classes.map(\.name), ["P5 English", "P6 Mathematics", "Sec 1 English", "Sec 2 Mathematics"])
        let p5 = try XCTUnwrap(classes.first { $0.name == "P5 English" })

        let session = try await service.getOrCreateTodaySession(classId: p5.id)
        let again = try await service.getOrCreateTodaySession(classId: p5.id)
        XCTAssertEqual(session.id, again.id)

        let roster = try await service.fetchRoster(sessionId: session.id)
        let nick = try XCTUnwrap(roster.first { $0.fullName == "Nick Chan" })
        XCTAssertNil(nick.status, "Nick starts as Not Here Yet so the demo can check him in")

        let receipt = try await service.markAttendance(sessionId: session.id, studentId: nick.studentId, status: .late, lateReason: "Bus")
        XCTAssertFalse(receipt.markedAt.isEmpty)
        var updated = try await service.fetchRoster(sessionId: session.id)
        XCTAssertEqual(updated.first { $0.studentId == nick.studentId }?.status, .late)

        try await service.clearAttendance(sessionId: session.id, studentId: nick.studentId)
        updated = try await service.fetchRoster(sessionId: session.id)
        XCTAssertNil(updated.first { $0.studentId == nick.studentId }?.status)

        let created = try await service.createStudentWithConsent(
            StudentInsert(fullName: "Demo Walk-in", school: nil, yearOfStudy: "P4"))
        var students = try await service.fetchAllStudents()
        XCTAssertTrue(students.contains { $0.id == created.id })

        let history = try await service.fetchStudentAttendanceHistory(studentId: nick.studentId)
        XCTAssertFalse(history.isEmpty)

        await MainActor.run { FeatureFlagStore.shared.applyDemoFlags() }
        let kiosk = try await service.fetchKioskEntries()
        XCTAssertEqual(kiosk.count, 24, "test_mode demo kiosk shows every enrolled student once")
        XCTAssertNotNil(kiosk.first { $0.fullName == "Lauren Tan" })

        XCTAssertEqual(DemoNetworkGuard.blockedRequestCount, 0, "demo mode must not even attempt a Supabase request")

        DemoStore.shared.reset()
        students = try await service.fetchAllStudents()
        XCTAssertFalse(students.contains { $0.id == created.id })
        XCTAssertEqual(students.count, 24)
    }

    func testGuardRefusesEverySupabaseRequestInDemoMode() async {
        DemoMode.setActive(true, persist: false)
        let session = DemoNetworkGuard.guardedSession()
        let url = URL(string: "https://your-project.supabase.co/rest/v1/attendance_records")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            _ = try await session.data(for: request)
            XCTFail("demo mode must not let a request through")
        } catch {
            XCTAssertEqual(DemoNetworkGuard.blockedRequestCount, 1)
        }
    }

    func testNonDemoAccountStillUsesTheRealSupabasePath() async {
        DemoMode.setActive(false, persist: false)
        XCTAssertFalse(DemoMode.isDemoEmail("teacher@thegoodcompanysg.dev"))

        DemoNetworkGuard.startRecordingRealRequests()
        _ = try? await AttendanceService.shared.fetchAllStudents()
        let urls = DemoNetworkGuard.stopRecordingRealRequests()

        XCTAssertTrue(urls.contains { $0.path.hasSuffix("/rest/v1/students") },
                      "outside demo mode the service must call Supabase, got \(urls)")
        XCTAssertEqual(DemoNetworkGuard.blockedRequestCount, 0)
    }

    @MainActor
    func testSigningInWithTheDemoEmailNeedsNoBackendAndSignOutLeavesDemo() async throws {
        let auth = AuthManager()
        try await auth.signIn(email: "Demo@TheGoodCompanySG.dev", password: "not-a-secret")
        XCTAssertTrue(DemoMode.isActive)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.currentProfile?.role, "admin")
        XCTAssertEqual(auth.currentProfile?.id, DemoMode.userId)
        XCTAssertTrue(FeatureFlagStore.shared.isEnabled(.testMode))
        XCTAssertFalse(FeatureFlagStore.shared.isEnabled(.pushNotifications))
        XCTAssertEqual(AttendanceService.shared.currentUserId, DemoMode.userId)

        try await auth.signOut()
        XCTAssertFalse(DemoMode.isActive)
        XCTAssertFalse(DemoMode.wasActiveOnLastLaunch)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.currentProfile)
    }

    /// The four familiar names are the only Easter egg: they are ordinary
    /// students with ordinary records and no special UI or messages.
    func testFamiliarNamesAreOrdinaryStudentsWithNoEasterEggUI() async throws {
        DemoMode.setActive(true, persist: false)
        DemoStore.shared.reset()
        let data = DemoStore.shared.snapshot
        let service = AttendanceService.shared
        func hasEmoji(_ text: String) -> Bool {
            text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        }
        for name in ["Lauren Tan", "Brian Chew", "Agrim Singh", "Nick Chan"] {
            let student = try XCTUnwrap(data.students.first { $0.fullName == name })
            XCTAssertNil(student.avatarUrl, "\(name) has no special photo")
            for text in [student.fullName, student.school ?? "", student.yearOfStudy ?? ""] {
                XCTAssertFalse(hasEmoji(text), "\(name) shows no emoji")
            }
            let cls = try XCTUnwrap(data.enrollments.first { $0.studentId == student.id })
            let session = try await service.getOrCreateTodaySession(classId: cls.classId)
            _ = try await service.markAttendance(sessionId: session.id, studentId: student.id, status: .present)
            let history = try await service.fetchStudentAttendanceHistory(studentId: student.id)
            XCTAssertFalse(history.isEmpty)
        }
        let messages = DemoStore.shared.snapshot.messages.map(\.body).joined(separator: " ")
        XCTAssertFalse(messages.localizedCaseInsensitiveContains("fun fact"))
        XCTAssertFalse(hasEmoji(messages))
        XCTAssertEqual(DemoNetworkGuard.blockedRequestCount, 0)
    }

    /// Airplane-mode rehearsal: cold launch → sign-in screen → demo sign-in → every
    /// screen's data → check-in, edits → reset → relaunch → sign-out, while every
    /// network request (Supabase client and URLSession.shared) is forced to fail.
    /// Passes only if the whole flow makes zero network attempts.
    @MainActor
    func testFullDemoFlowWorksWithEveryNetworkRequestFailing() async throws {
        URLProtocol.registerClass(FailingNetworkProtocol.self)
        FailingNetworkProtocol.reset()
        DemoNetworkGuard.startRecordingRealRequests()
        defer {
            URLProtocol.unregisterClass(FailingNetworkProtocol.self)
            _ = DemoNetworkGuard.stopRecordingRealRequests()
        }

        // Cold launch: the sign-in screen must appear without the network.
        let auth = AuthManager()
        let deadline = Date().addingTimeInterval(5)
        while auth.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(auth.isLoading, "sign-in screen must be reachable offline")
        XCTAssertFalse(auth.isAuthenticated)

        // Sign in through the normal sign-in call.
        try await auth.signIn(email: "demo@thegoodcompanysg.dev", password: "")
        XCTAssertTrue(DemoMode.isActive)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.currentProfile?.role, "admin")
        await FeatureFlagStore.shared.load()
        XCTAssertTrue(FeatureFlagStore.shared.isEnabled(.testMode))

        // Every screen's data.
        let service = AttendanceService.shared
        let classes = try await service.fetchMyClasses()
        XCTAssertEqual(classes.count, 4)
        for cls in classes {
            let loaded1 = try await service.fetchSessions(for: cls.id)
            XCTAssertFalse(loaded1.isEmpty)
            let loaded2 = try await service.fetchEnrollments(classId: cls.id)
            XCTAssertFalse(loaded2.isEmpty)
            _ = try await service.fetchTutorAssignments(classId: cls.id)
            let today = try await service.getOrCreateTodaySession(classId: cls.id)
            let loaded3 = try await service.fetchRoster(sessionId: today.id)
            XCTAssertFalse(loaded3.isEmpty)
        }
        let students = try await service.fetchAllStudents()
        XCTAssertEqual(students.count, 24)
        let loaded4 = try await service.fetchStudentResults()
        XCTAssertFalse(loaded4.isEmpty)
        let loaded5 = try await service.fetchTutors()
        XCTAssertFalse(loaded5.isEmpty)
        let loaded6 = try await service.fetchParents()
        XCTAssertFalse(loaded6.isEmpty)
        let kiosk = try await service.fetchKioskEntries()
        XCTAssertEqual(kiosk.count, 24)
        let loaded7 = try await service.loadStudySpace()
        XCTAssertEqual(loaded7.roster.count, 24)
        _ = try await service.fetchTodayDismissals()
        let loaded8 = try await service.fetchCorrectionRequests()
        XCTAssertFalse(loaded8.isEmpty)
        let loaded9 = try await service.fetchPrivacyNotice()
        XCTAssertNotNil(loaded9)
        let nick = try XCTUnwrap(students.first { $0.fullName == "Nick Chan" })
        let loaded10 = try await service.fetchStudentAttendanceHistory(studentId: nick.id)
        XCTAssertFalse(loaded10.isEmpty)
        let loaded11 = try await service.fetchCurrentConsent(studentId: nick.id)
        XCTAssertFalse(loaded11.isEmpty)
        _ = try await service.fetchStaffResultSlips(studentId: nick.id)
        _ = try await service.fetchMessages(studentId: nick.id)

        // Check-in and edits.
        let entry = try XCTUnwrap(kiosk.first { $0.fullName == "Nick Chan" })
        let status = try await service.markKioskSignIn(entry: entry)
        XCTAssertTrue(status == .present || status == .late)
        try await service.updateStudent(
            id: nick.id, StudentInsert(fullName: "Nick Chan", school: "Bukit View Primary", yearOfStudy: "P5"))
        try await service.upsertStudentResult(studentId: nick.id, subject: .english, grade: "AL2")
        let session = try await service.getOrCreateTodaySession(classId: classes[0].id)
        try await service.updateSessionNotes(id: session.id, notes: "Comprehension practice")

        // Reset, relaunch (still in demo, fresh data), sign out.
        auth.resetDemoData()
        let relaunched = AuthManager()
        XCTAssertTrue(relaunched.isAuthenticated, "a relaunch stays in demo mode offline")
        XCTAssertFalse(relaunched.isLoading)
        let loaded12 = try await service.fetchAllStudents()
        XCTAssertEqual(loaded12.count, 24)
        try await relaunched.signOut()
        XCTAssertFalse(DemoMode.isActive)
        XCTAssertFalse(relaunched.isAuthenticated)

        XCTAssertEqual(DemoNetworkGuard.blockedRequestCount, 0, "no Supabase request was even attempted")
        XCTAssertEqual(FailingNetworkProtocol.attempts, 0, "no URLSession.shared request was attempted")
        XCTAssertEqual(DemoNetworkGuard.stopRecordingRealRequests(), [], "no request left the demo path")
    }
}

/// Stands in for airplane mode: every URLSession.shared request fails immediately.
final class FailingNetworkProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var attempts: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); count = 0; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

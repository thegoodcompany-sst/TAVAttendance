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
}

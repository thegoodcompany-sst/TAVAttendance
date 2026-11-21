import XCTest
import PromptRouter
import UserNotifications
@testable import TAVAttendance

private class PromptMemory: PendingRoutePersistence {
    var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}
private final class FailingPromptMemory: PromptMemory {
    override func load() throws -> Data? { throw TeacherPromptError.unavailable }
    override func save(_ data: Data) throws { throw TeacherPromptError.unavailable }
}
@MainActor
private final class PromptEffectsSpy: TeacherPromptNotificationEffects {
    var removed: [UUID] = []
    var badges: [Int] = []
    func removeDelivered(lessonID: UUID) async { removed.append(lessonID) }
    func badge(_ count: Int) async { badges.append(count) }
}
@MainActor
private final class PromptServiceSpy: TeacherPromptServing {
    let demo: DemoTeacherPromptService
    var accountID: UUID { demo.accountID }
    var reads = 0
    var lists = 0
    var snoozes: [UUID] = []
    var submissions: [TeacherSubmitMutation] = []
    var confirmations: [TeacherSubmitMutation] = []
    var bulkMarks = 0
    var loseConfirmationResponse = false
    var loseMarkResponse = false
    var markFailureAt: Int?
    var afterMark: (() -> Void)?
    var marks: [TeacherMark] = []
    var submitFailure: TeacherPromptError?
    var readFailure: TeacherPromptError?
    var snoozeFailure: TeacherPromptError?
    var holdRead: CheckedContinuation<Void, Never>?
    var delayRead = false
    init(accountID: UUID = DemoMode.userId) { demo = DemoTeacherPromptService(accountID: accountID) }
    func lessons() async throws -> TeacherLessons { lists += 1; return try await demo.lessons() }
    func lesson(_ id: UUID) async throws -> TeacherLessonProjection {
        reads += 1
        if delayRead { await withCheckedContinuation { holdRead = $0 } }
        if let readFailure { throw readFailure }
        return try await demo.lesson(id)
    }
    func allPresent(_ m: TeacherRegisterMutation) async throws { bulkMarks += 1; try await demo.allPresent(m) }
    @discardableResult func mark(_ m: TeacherMark) async throws -> TeacherMarkReceipt {
        marks.append(m)
        if markFailureAt == marks.count { throw TeacherPromptError.conflict }
        let receipt = try await demo.mark(m)
        afterMark?()
        if loseMarkResponse { loseMarkResponse = false; throw TeacherPromptError.network }
        return receipt
    }
    func confirmAllPresentAndSubmit(_ m: TeacherSubmitMutation) async throws {
        confirmations.append(m)
        if let submitFailure { throw submitFailure }
        try await demo.confirmAllPresentAndSubmit(m)
        if loseConfirmationResponse { loseConfirmationResponse = false; throw TeacherPromptError.network }
    }
    func feedback(_ m: TeacherFeedbackMutation) async throws { try await demo.feedback(m) }
    func submit(_ m: TeacherSubmitMutation) async throws {
        submissions.append(m)
        if let submitFailure { throw submitFailure }
        try await demo.submit(m)
    }
    func snooze(_ id: UUID, mutationID: UUID) async throws {
        snoozes.append(mutationID)
        if let snoozeFailure { throw snoozeFailure }
        try await demo.snooze(id, mutationID: mutationID)
    }
}
@MainActor
private final class PromptRPCSpy: TeacherSessionRPC {
    let accountID = DemoMode.userId
    var calls: [String] = []
    var bodies: [[String: Any]] = []
    func call<P: Encodable, R: Decodable>(_ name: String, parameters: P, returning: R.Type) async throws -> R {
        calls.append(name)
        bodies.append(try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as! [String: Any])
        let data: Data
        if name == "register_device" {
            data = Data("{\"device_id\":\"50000000-0000-4000-8000-000000000001\",\"last_seen_at\":\"2027-01-07T13:00:00Z\",\"environment\":\"sandbox\"}".utf8)
        } else if name == "unregister_device" { data = Data("{\"revoked\":true}".utf8) }
        else if name == "my_lessons_today" { data = try JSONEncoder().encode(try await DemoTeacherPromptService().lessons()) }
        else if name == "lesson_for_prompt" { data = try JSONEncoder().encode(DemoTeacherPromptService().projection) }
        else {
            data = try JSONSerialization.data(withJSONObject: [
                "lesson_id": DemoTeacherPromptService.lessonID.uuidString, "replayed": false,
                "student_id": "20000000-0000-4000-8000-000000000001", "status": "present",
                "absence_informed": NSNull(), "marked_at": "2027-01-07T13:05:00.123456Z",
                "changed_count": 2, "register_revision": "4", "feedback_revision": "1",
                "submission_id": "50000000-0000-4000-8000-000000000001",
                "submitted_at": "2027-01-07T13:05:00Z", "snoozed_until": "2027-01-07T13:15:00Z",
                "next_prompt_at": "2027-01-07T13:15:00Z", "overdue_at": "2027-01-08T01:15:00Z"
            ])
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
}

@MainActor
final class TeacherPromptTests: XCTestCase {
    private let id = DemoTeacherPromptService.lessonID
    private var link: URL { URL(string: "tava://teacher/lesson/\(id.uuidString.lowercased())")! }
    private func enabled() -> TeacherPromptsGate {
        TeacherPromptsGate(master: true, workflowFlag: true, pushFlag: true, role: "teacher", active: true, optedIn: true)
    }
    private func payload(kind: String = "attendance", category: String = PromptAction.category) -> [AnyHashable: Any] {
        ["v": 1, "type": "teacher_prompt", "lesson_id": id.uuidString.lowercased(), "kind": kind,
         "aps": ["alert": ["title": "TAVA", "body": "Please review your lesson."], "sound": "default",
                 "category": category, "thread-id": "teacher-lesson:\(id.uuidString.lowercased())"]]
    }
    private func make(_ service: PromptServiceSpy, master: Bool = true, storage: PromptMemory = PromptMemory(),
                      effects: PromptEffectsSpy? = nil) -> TeacherPromptCoordinator {
        let c = TeacherPromptCoordinator(masterEnabled: master, persistence: storage,
            approvedHosts: ["prompts.example.test"], effects: effects ?? PromptEffectsSpy())
        c.update(authentication: .signedIn(PromptAccount(id: service.accountID, role: .teacher)), gate: enabled(), service: service)
        c.setUnlocked(true)
        return c
    }
    private func open(_ c: TeacherPromptCoordinator) async throws -> TeacherLessonModel {
        c.open(url: link); await c.waitForResolution()
        return try XCTUnwrap(c.lessonModel)
    }

    func testNotificationActionsStagesAndDedupe() async throws {
        for kind in ["heads_up", "attendance", "follow_up", "final"] {
            for action in [PromptAction.defaultIdentifier, "TAKE_ATTENDANCE", "SNOOZE_10"] {
                let service = PromptServiceSpy(), c = make(service)
                c.open(userInfo: payload(kind: kind), action: action, responseID: "request")
                await c.waitForResolution()
                let model = try XCTUnwrap(c.lessonModel)
                XCTAssertEqual(model.confirmingSnooze, action == "SNOOZE_10")
                XCTAssertTrue(service.snoozes.isEmpty)
                c.open(userInfo: payload(kind: kind), action: action, responseID: "request")
                await c.waitForResolution()
                XCTAssertEqual(service.reads, 1)
                if action == "SNOOZE_10" {
                    await model.confirmSnooze(); await model.confirmSnooze()
                    XCTAssertEqual(service.snoozes.count, 1)
                }
            }
        }
    }
    func testUnknownCategoryAndDisabledGatesMakeNoCalls() async {
        let s = PromptServiceSpy(), c = make(s)
        c.open(userInfo: payload(category: "other"), action: "TAKE_ATTENDANCE", responseID: "unknown")
        await c.waitForResolution(); XCTAssertEqual(s.reads, 0)
        let off = make(s, master: false)
        off.open(url: link); off.open(userInfo: payload(), action: "SNOOZE_10", responseID: "off")
        await off.foreground(); await off.loadLessons(); await off.waitForResolution()
        XCTAssertEqual(s.reads + s.lists, 0)
        var gate = enabled(); gate.workflowFlag = false
        c.update(authentication: .signedIn(PromptAccount(id: s.accountID, role: .teacher)), gate: gate, service: s)
        c.open(url: link); c.open(userInfo: payload(), action: "TAKE_ATTENDANCE", responseID: "disabled")
        await c.foreground(); XCTAssertEqual(s.reads + s.lists, 0)
        gate.workflowFlag = true; gate.pushFlag = false
        c.update(authentication: .signedIn(PromptAccount(id: s.accountID, role: .teacher)), gate: gate, service: s)
        c.open(userInfo: payload(), action: "TAKE_ATTENDANCE", responseID: "no-push")
        await c.waitForResolution(); XCTAssertEqual(s.reads, 0)
    }
    func testBothDeepLinksMalformedAndForeignRejected() async throws {
        let s = PromptServiceSpy(), c = make(s)
        _ = try await open(c)
        c.open(url: URL(string: "https://prompts.example.test/t/lesson/\(id.uuidString.lowercased())")!)
        await c.waitForResolution(); XCTAssertEqual(s.reads, 2)
        for text in ["https://foreign.test/t/lesson/\(id)", "tava://teacher/lesson/not-a-uuid", link.absoluteString + "?token=x"] {
            c.open(url: URL(string: text)!); await c.waitForResolution()
        }
        XCTAssertEqual(s.reads, 2)
    }
    func testSignedOutNavigationSurvivesRestart() async throws {
        let storage = PromptMemory(), s = PromptServiceSpy(), fx = PromptEffectsSpy()
        let first = TeacherPromptCoordinator(masterEnabled: true, persistence: storage, approvedHosts: [], effects: fx)
        first.open(url: link)
        XCTAssertEqual(first.state, .awaitingSignIn)
        let restored = make(s, storage: storage)
        await restored.waitForResolution()
        XCTAssertEqual(restored.lessonModel?.lessonID, id)
    }
    func testSwitchAccountDropsPendingSnoozeAndLateProjection() async {
        let s = PromptServiceSpy(), c = make(s)
        s.delayRead = true
        c.open(userInfo: payload(), action: "SNOOZE_10", responseID: "old-account")
        for _ in 0..<100 { if s.holdRead != nil { break }; await Task.yield() }
        let other = PromptServiceSpy(accountID: UUID())
        c.update(authentication: .signedIn(PromptAccount(id: other.accountID, role: .teacher)), gate: enabled(), service: other)
        s.holdRead?.resume(); s.holdRead = nil
        await Task.yield()
        XCTAssertNil(c.lessonModel); XCTAssertTrue(s.snoozes.isEmpty); XCTAssertEqual(other.reads, 0)
        XCTAssertEqual(c.state, .unavailable(.accountMismatch))
    }
    func testAllPresentPreservesMarksAdjustSubmitAndClearsPings() async throws {
        let s = PromptServiceSpy(), fx = PromptEffectsSpy(), c = make(s, effects: fx)
        let m = try await open(c)
        let original = try XCTUnwrap(m.projection)
        await m.allPresent()
        XCTAssertEqual(m.roster.map(\.status), [.present, .late, .absent, .present])
        XCTAssertEqual(m.roster[2].absence_informed, true)
        await m.mark(original.roster[1], status: .present)
        XCTAssertTrue(s.marks.isEmpty) // Preview edits are local until confirmation.
        await m.submit()
        XCTAssertEqual(s.marks.first(where: { $0.p_student_id == original.roster[1].id })?.p_observed_marked_at,
                       "2027-01-07T13:00:00.123456Z")
        XCTAssertEqual(s.marks.count, 3)
        XCTAssertTrue(s.confirmations.isEmpty)
        XCTAssertEqual(s.bulkMarks, 0)
        XCTAssertTrue(m.submitted)
        XCTAssertEqual(s.submissions.first?.p_expected_revision, s.demo.projection.lesson.register_revision)
        XCTAssertEqual(s.submissions.first?.p_expected_feedback_revision, "0")
        XCTAssertNotNil(s.submissions.first?.p_mutation_id)
        XCTAssertTrue(fx.removed.contains(id)); XCTAssertEqual(fx.badges.last, 0)
        let reads = s.reads
        c.open(userInfo: payload(), action: "SNOOZE_10", responseID: "after-submit")
        await c.waitForResolution()
        XCTAssertEqual(s.reads, reads); XCTAssertFalse(c.shouldPresent(userInfo: payload()))
    }
    func testNetworkRetryKeepsMutationAndConflictReloads() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        await m.allPresent()
        s.submitFailure = .network
        await m.submit()
        XCTAssertFalse(m.submitted); XCTAssertTrue(m.hasRetry); XCTAssertNotNil(m.projection)
        s.submitFailure = nil
        await m.retry()
        XCTAssertEqual(s.confirmations.count, 2); XCTAssertEqual(s.confirmations[0], s.confirmations[1])
        XCTAssertTrue(m.submitted)
        let s2 = PromptServiceSpy(), c2 = make(s2), m2 = try await open(c2)
        await m2.allPresent(); m2.notes = "lesson draft"
        await m2.saveNotes()
        s2.submitFailure = .conflict
        await m2.submit()
        XCTAssertEqual(m2.message, PromptStrings.stale); XCTAssertFalse(m2.hasRetry)
        XCTAssertEqual(m2.notes, "lesson draft"); XCTAssertFalse(m2.submitted)
    }
    func testSnoozeThirdAllowedFourthLimitedAndProjectionDisables() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        for _ in 0..<3 { m.confirmingSnooze = true; await m.confirmSnooze() }
        XCTAssertEqual(s.snoozes.count, 3); XCTAssertFalse(m.canSnooze)
        m.confirmingSnooze = true; await m.confirmSnooze()
        XCTAssertEqual(s.snoozes.count, 3)
        do { try await s.demo.snooze(id, mutationID: UUID()); XCTFail("Fourth snooze must fail") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .snoozeLimit) }
        let s2 = PromptServiceSpy(), c2 = make(s2), m2 = try await open(c2)
        s2.snoozeFailure = .snoozeLimit
        m2.confirmingSnooze = true; await m2.confirmSnooze()
        XCTAssertTrue(m2.snoozeLimited); XCTAssertFalse(m2.canSnooze)
        XCTAssertEqual(m2.message, PromptStrings.snoozeLimit)
    }
    func testDeniedSaveClearsSensitiveProjectionAndSessionExpiryPreservesNavigation() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        await m.allPresent()
        s.submitFailure = .unavailable
        await m.submit()
        XCTAssertNil(m.projection); XCTAssertEqual(m.notes, "")
        XCTAssertEqual(m.message, PromptStrings.unavailable)
        let s2 = PromptServiceSpy(), storage = PromptMemory(), c2 = make(s2, storage: storage)
        let m2 = try await open(c2)
        s2.snoozeFailure = .sessionExpired
        m2.confirmingSnooze = true; await m2.confirmSnooze()
        XCTAssertTrue(c2.needsSignIn); XCTAssertNil(c2.lessonModel)
        XCTAssertEqual(c2.state, .awaitingSignIn)
        let restored = make(s2, storage: storage)
        await restored.waitForResolution()
        XCTAssertFalse(try XCTUnwrap(restored.lessonModel).confirmingSnooze)
    }
    func testLockAndSignOutClearRosterDraftAndActions() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        m.notes = "temporary"; m.confirmingSnooze = true
        c.setUnlocked(false)
        XCTAssertNil(m.projection); XCTAssertEqual(m.notes, ""); XCTAssertFalse(m.confirmingSnooze)
        await m.submit(); await m.confirmSnooze()
        XCTAssertTrue(s.snoozes.isEmpty); XCTAssertTrue(s.submissions.isEmpty)
        _ = c.beginSignOut(); XCTAssertNil(c.lessonModel)
    }
    func testGateRequiresAllRegistrationInputsAndTeacherNeverUsesParentRPC() async {
        let all = enabled(); XCTAssertTrue(all.push)
        for index in 0..<7 {
            var gate = all
            switch index {
            case 0: gate.master = false
            case 1: gate.workflowFlag = false
            case 2: gate.pushFlag = false
            case 3: gate.optedIn = false
            case 4: gate.active = false
            case 5: gate.role = "tutor"
            default: gate.demo = true
            }
            XCTAssertFalse(gate.push)
        }
        for master in [true, false] {
            XCTAssertNotEqual(TeacherPromptsGate.tokenPath(master: master, role: "teacher", teacherRequest: false), .parent)
        }
        XCTAssertEqual(TeacherPromptsGate.tokenPath(master: false, role: "parent", teacherRequest: false), .parent)
        XCTAssertEqual(TeacherPromptsGate.tokenPath(master: true, role: nil, teacherRequest: false), .ignored)
        XCTAssertEqual(TeacherPromptsGate.tokenPath(master: true, role: nil, teacherRequest: true), .teacher)
    }
    func testExactRPCNamesNullableParametersAndServiceGate() async throws {
        let rpc = PromptRPCSpy()
        var allowed = false
        let service = TeacherPromptService(rpc: rpc, allowed: { allowed })
        do { _ = try await service.lessons(); XCTFail("Gate must refuse") } catch {}
        XCTAssertTrue(rpc.calls.isEmpty)
        allowed = true
        _ = try await service.lessons(); _ = try await service.lesson(id)
        let mutation = UUID()
        try await service.allPresent(TeacherRegisterMutation(p_lesson_id: id, p_expected_revision: "2", p_mutation_id: mutation))
        try await service.mark(TeacherMark(p_lesson_id: id, p_student_id: UUID(), p_status: .present,
            p_absence_informed: nil, p_observed_marked_at: nil, p_expected_revision: "3", p_mutation_id: UUID()))
        try await service.feedback(TeacherFeedbackMutation(p_lesson_id: id, p_body: "", p_expected_feedback_revision: "0", p_mutation_id: UUID()))
        try await service.submit(TeacherSubmitMutation(p_lesson_id: id, p_expected_revision: "4", p_expected_feedback_revision: "1", p_mutation_id: UUID()))
        try await service.confirmAllPresentAndSubmit(TeacherSubmitMutation(p_lesson_id: id,
            p_expected_revision: "2", p_expected_feedback_revision: "0", p_mutation_id: UUID()))
        try await service.snooze(id, mutationID: UUID())
        XCTAssertEqual(rpc.calls, ["my_lessons_today", "lesson_for_prompt", "mark_all_present", "mark_attendance", "save_feedback", "submit_lesson", "confirm_all_present_and_submit", "snooze_prompt"])
        XCTAssertTrue(rpc.bodies[0].isEmpty)
        XCTAssertTrue(rpc.bodies[3]["p_absence_informed"] is NSNull)
        XCTAssertTrue(rpc.bodies[3]["p_observed_marked_at"] is NSNull)
        XCTAssertEqual(rpc.bodies[7]["p_minutes"] as? Int, 10)
    }

    func testDemoListRouteRecoversFromUnavailableDeviceStorage() async throws {
        let s = PromptServiceSpy(), c = make(s, storage: FailingPromptMemory())
        var gate = enabled(); gate.demo = true
        c.update(authentication: .signedIn(PromptAccount(id: s.accountID, role: .teacher)), gate: gate, service: s)
        await c.loadLessons()
        let lesson = try XCTUnwrap(c.lessons?.lessons.first)
        c.openLesson(lesson.id); await c.waitForResolution()
        XCTAssertTrue(c.presented)
        XCTAssertNil(c.message)
        XCTAssertEqual(c.lessonModel?.lessonID, lesson.id)
        XCTAssertEqual(c.lessonModel?.canEdit, true)
        gate.demo = false
        c.update(authentication: .signedIn(PromptAccount(id: s.accountID, role: .teacher)), gate: gate, service: s)
        c.openLesson(lesson.id); await c.waitForResolution()
        XCTAssertNil(c.lessonModel); XCTAssertFalse(c.presented)
        XCTAssertEqual(c.message, PromptStrings.storageUnavailable) // Live storage still fails closed.
    }
    func testUnadjustedAllPresentUsesOnlyAtomicConfirmation() async throws {
        let s = PromptServiceSpy(), fx = PromptEffectsSpy(), c = make(s, effects: fx)
        let m = try await open(c)
        await m.allPresent()
        XCTAssertTrue(m.canSubmit)
        XCTAssertEqual(s.demo.projection.roster.filter { $0.status == nil }.count, 2)
        XCTAssertEqual(s.bulkMarks, 0); XCTAssertTrue(s.marks.isEmpty)
        // Snooze's projection reload must preserve the uncommitted review.
        m.confirmingSnooze = true; await m.confirmSnooze()
        XCTAssertTrue(m.reviewingAllPresent)
        s.loseConfirmationResponse = true
        await m.submit()
        XCTAssertTrue(m.hasRetry); XCTAssertFalse(m.submitted)
        XCTAssertNotNil(s.demo.projection.submission)
        await m.retry()
        XCTAssertEqual(s.confirmations.count, 2)
        XCTAssertEqual(s.confirmations[0], s.confirmations[1])
        XCTAssertTrue(s.submissions.isEmpty)
        XCTAssertTrue(s.marks.isEmpty); XCTAssertTrue(m.submitted)
        XCTAssertEqual(s.confirmations.first?.p_expected_revision, "2")
        XCTAssertEqual(s.confirmations.first?.p_expected_feedback_revision, "0")
        XCTAssertEqual(s.demo.projection.roster.map(\.status), [.present, .late, .absent, .present])
        XCTAssertEqual(s.demo.projection.roster[2].absence_informed, true)
        XCTAssertTrue(fx.removed.contains(id)); XCTAssertEqual(fx.badges.last, 0)
        try await s.demo.confirmAllPresentAndSubmit(XCTUnwrap(s.confirmations.first))
    }
    func testAdjustedSubmissionRetriesLostMarkResponseAndSubmitExactly() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        await m.allPresent(); await m.mark(m.roster[0], status: .late)
        s.loseMarkResponse = true
        await m.submit()
        XCTAssertTrue(m.hasRetry); XCTAssertFalse(m.submitted)
        s.submitFailure = .network
        await m.retry()
        XCTAssertEqual(s.marks.count, 3)
        XCTAssertEqual(s.marks[0], s.marks[1])
        XCTAssertTrue(m.hasRetry)
        s.submitFailure = nil
        await m.retry()
        XCTAssertEqual(s.marks.count, 3) // Completed rows are not sent again.
        XCTAssertEqual(s.submissions.count, 2)
        XCTAssertEqual(s.submissions[0], s.submissions[1])
        XCTAssertTrue(s.confirmations.isEmpty); XCTAssertTrue(m.submitted)
    }
    func testConflictDiscardsReviewAndNeverSilentlySubmits() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        await m.allPresent(); m.notes = "keep draft"
        await m.saveNotes()
        try await s.demo.mark(TeacherMark(p_lesson_id: id, p_student_id: m.roster[0].id,
            p_status: .late, p_absence_informed: nil, p_observed_marked_at: nil,
            p_expected_revision: "2", p_mutation_id: UUID()))
        await m.submit()
        XCTAssertFalse(m.submitted); XCTAssertFalse(m.hasRetry)
        XCTAssertFalse(m.reviewingAllPresent); XCTAssertFalse(m.canSubmit)
        XCTAssertEqual(m.notes, "keep draft"); XCTAssertEqual(m.message, PromptStrings.stale)
        XCTAssertEqual(s.demo.projection.roster[3].status, nil)
    }
    func testAdjustedPartialConflictAndSignOutStopRemainingWrites() async throws {
        for signOut in [false, true] {
            let s = PromptServiceSpy(), c = make(s), m = try await open(c)
            await m.allPresent(); await m.mark(m.roster[0], status: .late)
            if signOut { s.afterMark = { _ = c.beginSignOut() } }
            else { s.markFailureAt = 2 }
            await m.submit()
            XCTAssertTrue(s.submissions.isEmpty); XCTAssertTrue(s.confirmations.isEmpty)
            XCTAssertFalse(m.submitted); XCTAssertFalse(m.hasRetry)
            XCTAssertEqual(s.marks.count, signOut ? 1 : 2)
            if !signOut { XCTAssertFalse(m.reviewingAllPresent); XCTAssertEqual(m.message, PromptStrings.stale) }
        }
    }
    func testReviewRequiresSavedNotesAndClearBlocksConfirmation() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        await m.submit(); XCTAssertTrue(s.submissions.isEmpty)
        m.notes = "draft"; await m.allPresent()
        XCTAssertFalse(m.reviewingAllPresent)
        await m.saveNotes(); await m.allPresent()
        XCTAssertTrue(m.canSubmit)
        m.notes = "unsaved"; XCTAssertFalse(m.canSubmit)
        m.notes = "draft"
        await m.mark(m.roster[0], status: nil)
        XCTAssertFalse(m.canSubmit)
        await m.submit(); XCTAssertTrue(s.confirmations.isEmpty); XCTAssertTrue(s.submissions.isEmpty)
    }

    func testReviewRemainsProtectedThroughSnoozeAndFailedSubmit() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        XCTAssertFalse(m.preventsInteractiveDismissal)
        await m.allPresent()
        XCTAssertTrue(m.preventsInteractiveDismissal)
        m.confirmingSnooze = true; await m.confirmSnooze()
        XCTAssertEqual(m.message, PromptStrings.snoozed)
        XCTAssertFalse(m.confirmingSnooze)
        XCTAssertTrue(m.reviewingAllPresent)
        XCTAssertTrue(m.preventsInteractiveDismissal)

        s.submitFailure = .network
        await m.submit()
        XCTAssertFalse(m.submitted)
        XCTAssertEqual(m.message, PromptStrings.networkError)
        XCTAssertTrue(m.preventsInteractiveDismissal)
        s.submitFailure = nil
        await m.retry()
        XCTAssertTrue(m.submitted)
        XCTAssertNil(m.message)
        XCTAssertFalse(m.preventsInteractiveDismissal)
    }

    func testNotesDraftProtectsSheetUntilSavedOrInvalidated() async throws {
        let s = PromptServiceSpy(), c = make(s), m = try await open(c)
        m.notes = "draft"
        XCTAssertTrue(m.preventsInteractiveDismissal)
        await m.saveNotes()
        XCTAssertFalse(m.preventsInteractiveDismissal)
        m.notes = "unsaved"
        XCTAssertTrue(m.preventsInteractiveDismissal)
        // Learning that another device submitted must not silently drop this notes draft.
        let p = try XCTUnwrap(m.projection)
        try await s.demo.confirmAllPresentAndSubmit(TeacherSubmitMutation(p_lesson_id: m.lessonID,
            p_expected_revision: p.lesson.register_revision,
            p_expected_feedback_revision: p.feedback.revision, p_mutation_id: UUID()))
        await m.reload()
        XCTAssertTrue(m.submitted)
        XCTAssertEqual(m.notes, "unsaved")
        XCTAssertTrue(m.preventsInteractiveDismissal)
        m.invalidate()
        XCTAssertFalse(m.preventsInteractiveDismissal)
        XCTAssertEqual(m.notes, "")
    }

    func testCategoryActionsRequireForegroundAuthentication() async {
        let category = TeacherNotificationDelegate.category
        XCTAssertEqual(category.identifier, "TAVA_TEACHER_PROMPT")
        XCTAssertEqual(category.actions.map(\.identifier), ["TAKE_ATTENDANCE", "SNOOZE_10"])
        for action in category.actions {
            XCTAssertTrue(action.options.contains(.foreground))
            XCTAssertTrue(action.options.contains(.authenticationRequired))
        }
    }
    func testDeviceLifecycleUsesV2OnlyAndRevokesInstallation() async throws {
        let rpc = PromptRPCSpy(), memory = PromptMemory()
        let store = try TeacherPromptInstallation(storage: memory)
        let lifecycle = TeacherPushRegistrationLifecycle(service: TeacherDeviceService(rpc: rpc),
            installation: store, environment: .sandbox, retryDelay: { _ in })
        for optedIn in [false, true] {
            lifecycle.updateEligibility(TeacherPushEligibility(accountID: rpc.accountID, isActiveTeacherOrAdmin: true,
                teacherPrompts: true, teacherPromptPush: true, optedIn: optedIn, isDemo: false))
            XCTAssertEqual(lifecycle.acceptTokenCallback(for: lifecycle.generation), optedIn)
            lifecycle.didRegister(token: String(repeating: "ab", count: 32))
            await lifecycle.waitForIdle()
        }
        await lifecycle.beginSignOut()?.value
        XCTAssertEqual(rpc.calls, ["register_device", "unregister_device"])
        XCTAssertEqual(rpc.bodies.last?["p_installation_id"] as? String, store.installationID.uuidString)
        let restored = try TeacherPromptInstallation(storage: memory)
        XCTAssertEqual(restored.ownerID, rpc.accountID); XCTAssertNil(restored.deviceID)
    }
}

// Each test uses a unique host. Even parallel tests can only consume their own script.
private final class ConvexProtocolStub: URLProtocol {
    typealias Step = (URLRequest, [String: Any]) throws -> (Int, [String: Any])
    private static let lock = NSLock()
    private static var scripts: [String: [Step]] = [:]

    static func prepare(_ steps: [Step]) -> URL {
        let host = UUID().uuidString.lowercased() + ".invalid"
        lock.lock()
        scripts[host] = steps
        lock.unlock()
        return URL(string: "https://" + host)!
    }

    static func finish(_ url: URL) {
        lock.lock()
        let remaining = scripts.removeValue(forKey: url.host!)
        lock.unlock()
        XCTAssertEqual(remaining?.count, 0)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock()
        let host = request.url?.host ?? ""
        let step = Self.scripts[host]?.isEmpty == false ? Self.scripts[host]?.removeFirst() : nil
        Self.lock.unlock()
        do {
            let step = try XCTUnwrap(step, "Unexpected Convex request")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while true {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n < 0 { throw URLError(.cannotDecodeContentData) }
                    if n == 0 { break }
                    body.append(contentsOf: buffer.prefix(n))
                }
            }
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(envelope.keys), ["format", "path", "args"])
            XCTAssertEqual(envelope["format"] as? String, "json")
            let (code, json) = try step(request, envelope)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: json)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

@MainActor
final class ConvexTeacherTransportTests: XCTestCase {
    private let owner = UUID()
    private let email = "teacher@example.invalid"
    private let input = UUID().uuidString
    private let access = "stub.access"
    private let refresh = "stub.refresh"

    private func step(_ kind: String, _ path: String, token: String? = nil,
                      args: [String: Any] = [:], value: Any = NSNull(),
                      error: String? = nil, status: Int = 200) -> ConvexProtocolStub.Step {
        { request, envelope in
            XCTAssertEqual(request.url?.path, "/api/" + kind)
            XCTAssertEqual(envelope["path"] as? String, path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), token.map { "Bearer " + $0 })
            let actual = try XCTUnwrap(envelope["args"] as? NSDictionary)
            XCTAssertEqual(actual, args as NSDictionary)
            if let error { return (status, ["status": "error", "errorData": error]) }
            return (status, ["status": "success", "value": value])
        }
    }

    private var signIn: ConvexProtocolStub.Step {
        step("action", "auth:signIn", args: ["provider": "password",
             "params": ["email": email, "password": input, "flow": "signIn"]],
             value: ["tokens": ["token": access, "refreshToken": refresh]])
    }

    private func profile(_ token: String, id: UUID? = nil) -> ConvexProtocolStub.Step {
        step("query", "teacher:my_profile", token: token,
             value: ["id": (id ?? owner).uuidString, "display_name": "Test teacher", "role": "teacher",
                     "active": true, "teacher_prompts": true, "teacher_prompt_push": false])
    }

    private func session(_ url: URL, _ memory: PromptMemory) -> ConvexTeacherSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConvexProtocolStub.self]
        return ConvexTeacherSession(url: url, http: URLSession(configuration: configuration), storage: memory)
    }

    func testRefreshRotatesPersistedPairAndRestoredSessionSignsOut() async throws {
        let fresh = "rotated.access", next = "rotated.refresh"
        let url = ConvexProtocolStub.prepare([signIn,
            step("query", "teacher:my_profile", token: access, status: 401),
            step("action", "auth:signIn", args: ["refreshToken": refresh],
                 value: ["tokens": ["token": fresh, "refreshToken": next]]),
            profile(fresh), profile(fresh), step("action", "auth:signOut", token: fresh)])
        defer { ConvexProtocolStub.finish(url) }
        let memory = PromptMemory(), auth = session(url, memory)
        try await auth.signIn(email: email, password: input)
        let staff = try await auth.profile()
        XCTAssertEqual(staff.id, owner)
        XCTAssertEqual(staff.teacher_prompt_push, false)
        let stored = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(memory.data))
        XCTAssertEqual(stored, ["token": fresh, "refreshToken": next])
        let restored = session(url, memory)
        XCTAssertTrue(try restored.restore())
        _ = try await restored.profile()
        try await restored.signOut()
        XCTAssertFalse(try session(url, memory).restore())
    }

    func testMarkRequestAndAllDomainErrorCodes() async throws {
        let lesson = UUID(), student = UUID(), mutation = UUID()
        let mark = TeacherMark(p_lesson_id: lesson, p_student_id: student, p_status: nil,
                               p_absence_informed: nil, p_observed_marked_at: nil,
                               p_expected_revision: "3", p_mutation_id: mutation)
        let args: [String: Any] = ["p_lesson_id": lesson.uuidString, "p_student_id": student.uuidString,
            "p_status": NSNull(), "p_absence_informed": NSNull(), "p_observed_marked_at": NSNull(),
            "p_expected_revision": "3", "p_mutation_id": mutation.uuidString]
        let errors = TeacherPromptError.allCases.filter { $0.rawValue.hasPrefix("TP_") }
        let steps = errors.map { step("mutation", "teacher:mark_attendance", token: access,
                                      args: args, error: $0.rawValue, status: 560) }
        let url = ConvexProtocolStub.prepare([signIn, profile(access)] + steps +
            [step("query", "teacher:my_lessons_today", token: access, error: "UNKNOWN")])
        defer { ConvexProtocolStub.finish(url) }
        let auth = session(url, PromptMemory())
        try await auth.signIn(email: email, password: input)
        _ = try await auth.profile()
        let rpc = TeacherPromptRPC(accountID: owner, session: auth, allowed: { true }, masterEnabled: { true })
        let service = TeacherPromptService(rpc: rpc, allowed: { true })
        for expected in errors {
            do { _ = try await service.mark(mark); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? TeacherPromptError, expected) }
        }
        do { _ = try await service.lessons(); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .network) }
    }

    func testOriginalSessionCanOnlyUnregisterAfterRuntimeGateCloses() async throws {
        let installation = UUID(), device = UUID(), other = UUID()
        let args = ["p_installation_id": installation.uuidString]
        let apns = String(repeating: "01", count: 32)
        let url = ConvexProtocolStub.prepare([signIn, profile(access),
            step("mutation", "devices:register_device", token: access,
                 args: args.merging(["p_token": apns, "p_environment": "sandbox"]) { _, v in v },
                 value: ["device_id": device.uuidString, "environment": "sandbox", "last_seen_at": "now"]),
            step("mutation", "devices:unregister_device", token: access, args: args, value: ["revoked": true]),
            step("action", "auth:signOut", token: access), signIn, profile(access, id: other)])
        defer { ConvexProtocolStub.finish(url) }
        let auth = session(url, PromptMemory())
        try await auth.signIn(email: email, password: input)
        _ = try await auth.profile()
        var allowed = true, master = true
        let rpc = TeacherPromptRPC(accountID: owner, session: auth, allowed: { allowed }, masterEnabled: { master })
        let devices = TeacherDeviceService(rpc: rpc)
        let registered = try await devices.register(installationID: installation, token: apns, environment: "sandbox")
        XCTAssertEqual(registered.device_id, device)
        allowed = false
        do {
            _ = try await devices.register(installationID: installation, token: apns, environment: "sandbox")
            XCTFail("Registration must require workflow access")
        } catch { XCTAssertEqual(error as? TeacherPromptError, .disabled) }
        try await devices.unregister(installationID: installation)
        master = false
        do { try await devices.unregister(installationID: installation); XCTFail("Master gate closed") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .disabled) }
        master = true
        try await auth.signOut()
        try await auth.signIn(email: email, password: input)
        _ = try await auth.profile()
        do { try await devices.unregister(installationID: installation); XCTFail("Owner changed") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .sessionExpired) }
    }

    func testWorkflowGateIsCheckedAgainAfterRefresh() async throws {
        let url = ConvexProtocolStub.prepare([signIn, profile(access),
            step("query", "teacher:my_lessons_today", token: access, status: 401),
            step("action", "auth:signIn", args: ["refreshToken": refresh],
                 value: ["tokens": ["token": "rotated", "refreshToken": "next"]])])
        defer { ConvexProtocolStub.finish(url) }
        let auth = session(url, PromptMemory())
        try await auth.signIn(email: email, password: input)
        _ = try await auth.profile()
        var checks = 0
        let rpc = TeacherPromptRPC(accountID: owner, session: auth, allowed: {
            checks += 1
            return checks == 1
        }, masterEnabled: { true })
        do { _ = try await TeacherPromptService(rpc: rpc, allowed: { true }).lessons(); XCTFail("Gate closed") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .disabled) }
        XCTAssertEqual(checks, 2)
    }

    func testRemoteSignOutFailureStillForgetsStoredCredentials() async throws {
        let url = ConvexProtocolStub.prepare([signIn, { _, _ in (503, [:]) }])
        defer { ConvexProtocolStub.finish(url) }
        let memory = PromptMemory(), auth = session(url, memory)
        try await auth.signIn(email: email, password: input)
        do { try await auth.signOut(); XCTFail("Expected remote failure") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .network) }
        XCTAssertFalse(try session(url, memory).restore())
    }

    func testRejectedRefreshAndInvalidPasswordRequireSignIn() async throws {
        let url = ConvexProtocolStub.prepare([signIn,
            step("query", "teacher:my_profile", token: access, error: "sessionExpired"),
            step("action", "auth:signIn", args: ["refreshToken": refresh], value: ["tokens": NSNull()]),
            { _, _ in (560, ["status": "error", "errorMessage": "Invalid credentials"]) }])
        defer { ConvexProtocolStub.finish(url) }
        let auth = session(url, PromptMemory())
        try await auth.signIn(email: email, password: input)
        do { _ = try await auth.profile(); XCTFail("Refresh rejected") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .sessionExpired) }
        do { try await auth.signIn(email: email, password: input); XCTFail("Credentials rejected") }
        catch { XCTAssertEqual(error as? TeacherPromptError, .sessionExpired) }
    }
}

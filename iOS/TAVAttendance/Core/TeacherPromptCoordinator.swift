import Foundation
import Combine
import PromptRouter

private final class TeacherPromptEphemeralRoute: PendingRoutePersistence {
    private var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}

@MainActor
final class TeacherPromptCoordinator: ObservableObject {
    static let shared = TeacherPromptCoordinator(
        masterEnabled: TeacherPromptsGate.masterEnabled,
        persistence: defaultPersistence(),
        approvedHosts: TeacherPromptsGate.approvedHosts,
        effects: TeacherPromptSystemNotifications())

    private static func defaultPersistence() -> any PendingRoutePersistence {
        if TeacherPromptsGate.demoLaunch { return TeacherPromptEphemeralRoute() }
        return TeacherPromptKeychain("route-v1")
    }

    @Published private(set) var gate = TeacherPromptsGate()
    @Published private(set) var state: PromptRouterState = .idle
    @Published private(set) var lessonModel: TeacherLessonModel?
    @Published private(set) var lessons: TeacherLessons?
    @Published private(set) var message: String?
    @Published var presented = false
    @Published var needsSignIn = false
    @Published private(set) var listBusy = false
    @Published private(set) var optedIn = false
    private(set) var authentication: PromptAuthentication = .restoring
    @Published private(set) var unlocked = false
    private(set) var registration: TeacherPushRegistration?
    private(set) var service: (any TeacherPromptServing)?
    private let masterEnabled: Bool
    private let persistence: any PendingRoutePersistence
    private let approvedHosts: Set<String>
    private var effects: any TeacherPromptNotificationEffects
    private var router: PromptRouter?
    private var demoPersistence: TeacherPromptEphemeralRoute?
    private var resolutionTask: Task<Void, Never>?
    private var resolvingID: UUID?
    private var generation = UUID()
    private var completed: Set<UUID> = []
    private var registrationAccount: UUID?
    var accountID: UUID? {
        if case .signedIn(let account) = authentication { return account.id }
        return nil
    }
    var currentRole: String? {
        if case .signedIn(let account) = authentication { return account.role.rawValue }
        return nil
    }
    init(masterEnabled: Bool, persistence: any PendingRoutePersistence,
         approvedHosts: Set<String>, effects: any TeacherPromptNotificationEffects) {
        self.masterEnabled = masterEnabled; self.persistence = persistence
        self.approvedHosts = approvedHosts; self.effects = effects
        gate.master = masterEnabled
        if masterEnabled { ensureRouter() }
    }
    private func ensureRouter() {
        guard masterEnabled, router == nil else { return }
        do {
            router = try PromptRouter(approvedHosts: approvedHosts,
                persistence: demoPersistence ?? persistence, now: Date())
            message = nil
        }
        catch { message = PromptStrings.storageUnavailable }
    }

    /// Called only after profile + flags load; legacy tutor is deliberately not teacher.
    func configure(profile: Profile?, session: ConvexTeacherSession? = nil) {
        guard masterEnabled else { return }
        guard let profile else { update(authentication: .signedOut, gate: TeacherPromptsGate(master: true), service: nil); return }
        let demo = DemoMode.isActive
        optedIn = !demo && UserDefaults.standard.bool(forKey: "teacherPrompts.optIn.\(profile.id.uuidString)")
        let nextGate = TeacherPromptsGate(master: masterEnabled,
            workflowFlag: FeatureFlagStore.shared.isEnabled(.teacherPrompts),
            pushFlag: FeatureFlagStore.shared.isEnabled(.teacherPromptPush), role: profile.role,
            active: demo || profile.active == true, optedIn: optedIn, demo: demo)
        let account = PromptAccount(id: profile.id, role: PromptAccount.Role(rawValue: profile.role) ?? .other,
                                    isActive: nextGate.active)
        var nextService = service
        let replace = service?.accountID != profile.id || gate.demo != demo
        if replace {
            _ = registration?.lifecycle.beginSignOut()
            registration = nil; registrationAccount = nil; nextService = nil
            if demo {
                nextService = DemoTeacherPromptService(accountID: profile.id)
                effects = TeacherPromptDemoNotifications()
            } else if let session, session.accountID == profile.id {
                effects = TeacherPromptSystemNotifications()
                let rpc = TeacherPromptRPC(accountID: profile.id, session: session,
                    allowed: { [weak self] in self?.gate.workflow == true && self?.accountID == profile.id },
                    masterEnabled: { TeacherPromptsGate.masterEnabled })
                nextService = TeacherPromptService(rpc: rpc, allowed: { [weak self] in
                    self?.gate.workflow == true && self?.accountID == profile.id && self?.unlocked == true
                })
                do {
                    let store = try TeacherPromptInstallation(storage: TeacherPromptKeychain("installation-v1"))
                    // Build value must match the eventual signed entitlement, never DEBUG.
                    // Missing capability/environment disables APNs. See HUMANS.md pilot TODO.
                    let value = Bundle.main.object(forInfoDictionaryKey: "TEACHER_PROMPTS_APNS_ENVIRONMENT") as? String ?? ""
                    let environment = TeacherAPNSEnvironment(signedEntitlement: value)
                    registration = TeacherPushRegistration(rpc: rpc, installation: store, environment: environment)
                    registrationAccount = profile.id
                    registration?.lifecycle.showTodaysLessons = { [weak self] in self?.message = $0 }
                    registration?.lifecycle.clearLocalActions = { [weak self] in self?.lessonModel?.confirmingSnooze = false }
                } catch { message = PromptStrings.storageUnavailable }
            }
        }
        update(authentication: .signedIn(account), gate: nextGate, service: nextService, force: replace)
        updateRegistration()
        if gate.push { Task { await requestRegistration() } }
    }
    /// Also used by unit tests, injecting a service without Auth, APNs or a database.
    func update(authentication: PromptAuthentication, gate: TeacherPromptsGate,
                service: (any TeacherPromptServing)?, force: Bool = false) {
        guard masterEnabled else { return }
        let changedAccount = self.accountID != service?.accountID
        if force || self.authentication != authentication || self.gate != gate {
            invalidatePresentation()
            lessons = nil
            if changedAccount { completed = [] }
        }
        // Demo routing must never depend on Keychain, including entry after launch
        // or recovery from a failed device-store initialization on unsigned simulators.
        if self.gate.demo != gate.demo {
            router = nil
            demoPersistence = gate.demo ? TeacherPromptEphemeralRoute() : nil
        }
        self.authentication = authentication
        self.gate = gate
        self.service = service
        advanceContext()
    }
    func loadingProfile(_ id: UUID) {
        guard masterEnabled else { return }
        invalidatePresentation(); lessons = nil
        authentication = .loadingProfile(id)
        advanceContext()
    }
    func setUnlocked(_ value: Bool) {
        guard masterEnabled, value != unlocked else { return }
        unlocked = value
        if !value { invalidatePresentation(); lessons = nil }
        advanceContext()
    }
    private func advanceContext() {
        ensureRouter()
        perform { try router?.update(context: PromptContext(authentication: authentication,
            teacherPromptsEnabled: gate.workflow, isUnlocked: unlocked), now: Date()) }
    }
    private func invalidatePresentation() {
        generation = UUID(); resolutionTask?.cancel(); resolutionTask = nil; resolvingID = nil
        lessonModel?.invalidate(); lessonModel = nil; presented = false; listBusy = false
    }
    func setOptedIn(_ value: Bool) async {
        guard masterEnabled, let id = accountID, gate.workflow, !gate.demo else { return }
        UserDefaults.standard.set(value, forKey: "teacherPrompts.optIn.\(id.uuidString)")
        optedIn = value; gate.optedIn = value
        lessonModel?.confirmingSnooze = false
        updateRegistration()
        if value {
            if let registration { await registration.requestIfEligible() }
            else { message = PromptStrings.pushUnavailable }
        }
    }
    private func updateRegistration() {
        guard let id = accountID, registrationAccount == id else { return }
        registration?.lifecycle.updateEligibility(TeacherPushEligibility(accountID: id,
            isActiveTeacherOrAdmin: gate.staff, teacherPrompts: gate.workflow,
            teacherPromptPush: gate.pushFlag, optedIn: optedIn, isDemo: gate.demo))
    }
    func requestRegistration() async {
        guard gate.push else { return }
        if let registration { await registration.requestIfEligible() }
        else { message = PromptStrings.pushUnavailable }
    }
    /// Clears local actions synchronously; AuthManager awaits the bounded cleanup first.
    func beginSignOut() -> Task<Void, Never>? {
        guard masterEnabled else { return nil }
        invalidatePresentation(); lessons = nil; completed = []
        authentication = .signedOut; gate.workflowFlag = false
        advanceContext()
        let task = registration?.lifecycle.beginSignOut()
        registration = nil; registrationAccount = nil; service = nil
        Task { await effects.badge(0) }
        return task
    }
    func open(url: URL) {
        guard masterEnabled else { return }
        if accountID != nil && !gate.workflow { return }
        ensureRouter()
        perform { _ = try router?.open(link: url.absoluteString, now: Date()) }
    }
    func openLesson(_ id: UUID) {
        guard gate.workflow, unlocked else { return }
        open(url: URL(string: "tava://teacher/lesson/\(id.uuidString.lowercased())")!)
    }
    func open(userInfo: [AnyHashable: Any], action: String, responseID: String) {
        guard masterEnabled else { return }
        if accountID != nil && (!gate.workflow || !gate.pushFlag) { return }
        guard let destination = PromptParser(approvedHosts: approvedHosts).parse(userInfo: userInfo, actionIdentifier: action),
              !completed.contains(destination.lessonID) else { return }
        ensureRouter()
        perform { _ = try router?.open(userInfo: userInfo, actionIdentifier: action, responseID: responseID, now: Date()) }
    }
    func shouldPresent(userInfo: [AnyHashable: Any]) -> Bool {
        guard gate.workflow, gate.pushFlag,
              let destination = PromptParser(approvedHosts: approvedHosts).parse(userInfo: userInfo,
                actionIdentifier: PromptAction.defaultIdentifier) else { return false }
        return !completed.contains(destination.lessonID)
    }
    func close() {
        invalidatePresentation()
        perform { try router?.discard() }
    }
    func retry() { perform { try router?.retry(now: Date()) } }
    func foreground() async {
        guard masterEnabled else { return }
        perform { try router?.refresh(now: Date()) }
        registration?.lifecycle.retryPendingRevocation()
        guard gate.workflow, unlocked else { return }
        await loadLessons()
    }
    func loadLessons() async {
        guard gate.workflow, unlocked, let service, service.accountID == accountID, !listBusy else { return }
        let started = generation
        listBusy = true
        defer { if started == generation { listBusy = false } }
        do {
            let result = try await service.lessons()
            guard started == generation, gate.workflow, unlocked else { return }
            lessons = result; message = nil
            let done = (result.lessons + result.backlog).filter { $0.state == "submitted" }.map(\.id)
            completed.formUnion(done)
            for id in done { await effects.removeDelivered(lessonID: id) }
            guard started == generation else { return }
            await effects.badge(result.outstanding_count)
        } catch {
            guard started == generation else { return }
            message = (error as? TeacherPromptError ?? .network).message
            if error as? TeacherPromptError == .sessionExpired { expireSession(lessonID: nil) }
        }
    }
    private func submitted(_ id: UUID) async {
        completed.insert(id)
        await effects.removeDelivered(lessonID: id)
        await loadLessons()
    }
    private func expireSession(lessonID: UUID?) {
        if let lessonID {
            perform { _ = try router?.open(link: "tava://teacher/lesson/\(lessonID.uuidString.lowercased())", now: Date()) }
        }
        invalidatePresentation(); lessons = nil; authentication = .signedOut
        needsSignIn = true
        advanceContext()
        message = PromptStrings.signIn
    }
    private func perform(_ event: () throws -> Void) {
        guard masterEnabled else { return }
        do { try event() }
        catch { message = PromptStrings.storageUnavailable }
        drive()
    }
    private func drive() {
        guard let router else { return }
        if state != router.state {
            lessonModel?.invalidate(); lessonModel = nil
            state = router.state
        }
        guard case .resolving(let request) = state else {
            resolutionTask?.cancel(); resolutionTask = nil; resolvingID = nil
            if case .unavailable = state { message = PromptStrings.unavailable; presented = unlocked && gate.workflow }
            return
        }
        guard resolvingID != request.id, gate.workflow, unlocked,
              let service, service.accountID == request.accountID else { return }
        resolvingID = request.id
        resolutionTask?.cancel()
        presented = true
        let started = generation
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let projection = try await service.lesson(request.lessonID)
                guard !Task.isCancelled, generation == started, router.state == .resolving(request) else { return }
                guard projection.lesson.id == request.lessonID else { throw TeacherPromptError.unavailable }
                try router.complete(request, outcome: .authorized, now: Date())
                guard case .ready(let ready) = router.state else { drive(); return }
                state = router.state
                lessonModel = TeacherLessonModel(projection: projection, service: service,
                    needsSnoozeConfirmation: ready.needsSnoozeConfirmation,
                    allowed: { [weak self] in self?.generation == started && self?.gate.workflow == true && self?.unlocked == true && self?.accountID == request.accountID },
                    didSubmit: { [weak self] id in await self?.submitted(id) },
                    sessionExpired: { [weak self] id in self?.expireSession(lessonID: id) })
                if projection.submission != nil || projection.lesson.state == "submitted" { await submitted(request.lessonID) }
            } catch {
                guard !Task.isCancelled, generation == started else { return }
                if router.state == .unavailable(.persistence) {
                    state = router.state; message = PromptStrings.storageUnavailable
                    return
                }
                let error = error as? TeacherPromptError ?? .network
                let outcome: PromptResolutionOutcome = error == .sessionExpired ? .sessionExpired :
                    (error == .unavailable || error == .disabled ? .denied : .networkFailure)
                perform { try router.complete(request, outcome: outcome, now: Date()) }
                message = error.message
                if error == .sessionExpired { expireSession(lessonID: nil) }
            }
        }
    }
    // Tests wait for actual resolution, without wall-clock sleeps.
    func waitForResolution() async { await resolutionTask?.value }
}

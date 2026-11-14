// Integration sketch only. No UIKit/UserNotifications dependency in Package Sources.
#if canImport(UIKit) && canImport(UserNotifications)
import Foundation
import UIKit
import UserNotifications
import PromptRouter

/// A Foundation-only persistence implementation can also be used by the real app.
/// Store under Application Support with iOS data protection, excluded from backups.
/// This is intentionally separate from PendingAttendanceStore (which clears on logout).
final class PromptFilePersistence: PendingRoutePersistence {
    private let fileURL: URL
    init(fileURL: URL) { self.fileURL = fileURL }
    func load() throws -> Data? {
        do { return try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
    func save(_ data: Data) throws {
        var directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

enum TeacherPromptServiceError: Error { case sessionExpired }

/// Implement in Services using an account-bound session and shaped RPCs only.
/// resolve calls lesson_for_prompt(p_lesson_id); a successful HTTP response alone is
/// insufficient: decode the expected projection before reporting .authorized.
/// No denied/network response may be treated as an empty but authorized lesson.
@MainActor
protocol TeacherPromptService {
    func resolve(_ request: PromptResolution) async -> PromptResolutionOutcome
    /// Calls snooze_prompt(p_lesson_id, p_minutes: 10, p_mutation_id), deriving actor
    /// from the same authenticated session. Never persists/retries writes offline.
    func snooze(lessonID: UUID, accountID: UUID, mutationID: UUID) async throws
    /// Calls my_lessons_today() with no date override; returns outstanding_count.
    func outstandingCount(accountID: UUID) async throws -> Int
}

@MainActor
final class TeacherPromptCoordinator {
    let router: PromptRouter
    private let service: any TeacherPromptService
    private var resolutionTask: Task<Void, Never>?
    private var resolutionID: UUID?
    private var snoozeTask: Task<Void, Never>?
    private var confirmation: ReadyPrompt?
    private var publishedState: PromptRouterState?
    // Host clears roster, feedback drafts, and queued actions whenever leaving .ready.
    var render: (PromptRouterState) -> Void = { _ in }
    var showTodaysLessons: (String) -> Void = { _ in }

    init(router: PromptRouter, service: any TeacherPromptService) {
        self.router = router
        self.service = service
    }

    func open(url: URL) {
        perform { _ = try router.open(link: url.absoluteString, now: Date()) }
    }

    func open(userInfo: [AnyHashable: Any], action: String, responseID: String) {
        perform { _ = try router.open(userInfo: userInfo, actionIdentifier: action, responseID: responseID, now: Date()) }
    }

    /// AuthManager sends .restoring/.loadingProfile first, then .signedIn only after
    /// fetchProfile + flags finish. Send lock events BEFORE hiding/showing protected UI.
    func update(context: PromptContext) {
        if router.context != context {
            confirmation = nil
            snoozeTask?.cancel()
            snoozeTask = nil
        }
        perform { try router.update(context: context, now: Date()) }
    }

    func retry() { perform { try router.retry(now: Date()) } }

    func foreground() {
        perform { try router.refresh(now: Date()) }
        guard case .signedIn(let account) = router.context.authentication,
              account.isActive, account.role == .teacher || account.role == .admin,
              router.context.teacherPromptsEnabled, router.context.isUnlocked else { return }
        let context = router.context
        Task {
            do {
                let count = try await service.outstandingCount(accountID: account.id)
                guard router.context == context else { return }
                try await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
            } catch {
                guard router.context == context else { return }
                showTodaysLessons(PromptStrings.pushUnavailable)
            }
        }
    }

    /// Invoked only by the visible confirmation button, never by a notification callback.
    func confirmSnooze(_ ready: ReadyPrompt) {
        guard confirmation == ready, router.state == .ready(ready),
              case .signedIn(let account) = router.context.authentication,
              account.id == ready.accountID, account.isActive,
              account.role == .teacher || account.role == .admin,
              router.context.isUnlocked, router.context.teacherPromptsEnabled else { return }
        confirmation = nil // One explicit confirmation, one fresh mutation UUID.
        snoozeTask = Task {
            do {
                try Task.checkCancellation()
                try await service.snooze(lessonID: ready.lessonID, accountID: ready.accountID, mutationID: UUID())
                guard !Task.isCancelled, router.state == .ready(ready) else { return }
                foreground()
            } catch TeacherPromptServiceError.sessionExpired {
                guard !Task.isCancelled, router.state == .ready(ready) else { return }
                // Retain actor-bound NAVIGATION; require a new confirmation after login.
                perform {
                    _ = try router.open(link: "tava://teacher/lesson/\(ready.lessonID.uuidString.lowercased())", now: Date())
                    try router.update(context: PromptContext(authentication: .signedOut), now: Date())
                }
            } catch {
                guard !Task.isCancelled, router.state == .ready(ready) else { return }
                showTodaysLessons(PromptStrings.pushUnavailable)
            }
        }
    }

    private func perform(_ event: () throws -> Void) {
        do { try event() }
        catch { showTodaysLessons(PromptStrings.storageUnavailable) }
        drive()
    }

    private func drive() {
        let state = router.state
        if state != publishedState {
            publishedState = state
            if case .ready(let ready) = state, ready.needsSnoozeConfirmation { confirmation = ready }
            else { confirmation = nil; snoozeTask?.cancel(); snoozeTask = nil }
            render(state)
        }
        guard case .resolving(let request) = state else {
            resolutionTask?.cancel(); resolutionTask = nil; resolutionID = nil
            return
        }
        guard resolutionID != request.id else { return }
        resolutionTask?.cancel()
        resolutionID = request.id
        resolutionTask = Task {
            let result = await service.resolve(request)
            guard !Task.isCancelled else { return }
            perform { try router.complete(request, outcome: result, now: Date()) }
        }
    }
}

/// Retain on the app delegate for the lifetime of the process: center.delegate is weak.
/// Merge with existing parent notification handling when integrated, not a second delegate.
final class TeacherNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor private let coordinator: TeacherPromptCoordinator
    @MainActor init(coordinator: TeacherPromptCoordinator) { self.coordinator = coordinator }

    static var category: UNNotificationCategory {
        let attendance = UNNotificationAction(identifier: PromptAction.takeAttendance.rawValue,
            title: PromptStrings.takeAttendance, options: [.foreground, .authenticationRequired])
        let snooze = UNNotificationAction(identifier: PromptAction.snoozeTen.rawValue,
            title: PromptStrings.snoozeTen, options: [.foreground, .authenticationRequired])
        return UNNotificationCategory(identifier: PromptAction.category, actions: [attendance, snooze],
                                      intentIdentifiers: [], options: [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() } // No network/auth wait in the OS callback.
            let request = response.notification.request
            coordinator.open(userInfo: request.content.userInfo, action: response.actionIdentifier,
                             responseID: request.identifier)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Foreground receipt refreshes the list/badge; it NEVER navigates or submits.
        Task { @MainActor in
            coordinator.foreground()
            completionHandler([])
        }
    }
}
#endif

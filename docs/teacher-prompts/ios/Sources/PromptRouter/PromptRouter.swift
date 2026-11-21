import Foundation

public enum PromptAction: String, Codable, Equatable {
    case takeAttendance = "TAKE_ATTENDANCE"
    case snoozeTen = "SNOOZE_10"

    public static let category = "TAVA_TEACHER_PROMPT"
    public static let defaultIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"

    public init?(identifier: String) {
        if identifier == Self.defaultIdentifier { self = .takeAttendance }
        else if let action = Self(rawValue: identifier) { self = action }
        else { return nil } // Dismissal and unknown actions do nothing.
    }
}

public enum PromptKind: String, Codable, CaseIterable {
    case headsUp = "heads_up", attendance, followUp = "follow_up", final
}

public struct PromptDestination: Equatable {
    public let lessonID: UUID
    public let action: PromptAction
}

/// Only canonical locators are accepted. No URL fetch, auth token, or roster data.
public struct PromptParser {
    public let approvedHosts: Set<String>

    public init(approvedHosts: Set<String>) { self.approvedHosts = approvedHosts }

    public static func lessonID(_ value: String) -> UUID? {
        let pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        guard value.utf8.count == 36,
              value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return UUID(uuidString: value)
    }

    public func parse(url: URL) -> PromptDestination? { parse(link: url.absoluteString) }

    public func parse(link: String) -> PromptDestination? {
        guard let parts = URLComponents(string: link), parts.user == nil,
              parts.password == nil, parts.port == nil, parts.query == nil,
              parts.fragment == nil, let host = parts.host else { return nil }
        let prefix: String
        if parts.scheme == "https", approvedHosts.contains(host),
           host.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil {
            prefix = "https://\(host)/t/lesson/"
        } else if parts.scheme == "tava", host == "teacher" {
            prefix = "tava://teacher/lesson/"
        } else { return nil }
        guard link.hasPrefix(prefix), let id = Self.lessonID(String(link.dropFirst(prefix.count))),
              link == prefix + id.uuidString.lowercased() else { return nil }
        return PromptDestination(lessonID: id, action: .takeAttendance)
    }

    public func parse(userInfo: [AnyHashable: Any], actionIdentifier: String) -> PromptDestination? {
        // Reject Boolean "true" as version 1, including NSNumber from JSONSerialization.
        guard Set(userInfo.keys.compactMap { $0 as? String }) == Set(["aps", "v", "type", "lesson_id", "kind"]),
              userInfo.count == 5,
              let version = userInfo["v"] as? NSNumber,
              String(cString: version.objCType) != "c", version.doubleValue == 1,
              userInfo["type"] as? String == "teacher_prompt",
              let rawID = userInfo["lesson_id"] as? String, let id = Self.lessonID(rawID),
              let rawKind = userInfo["kind"] as? String, PromptKind(rawValue: rawKind) != nil,
              let action = PromptAction(identifier: actionIdentifier),
              let aps = userInfo["aps"] as? [String: Any],
              Set(aps.keys) == Set(["alert", "sound", "category", "thread-id"]),
              aps["category"] as? String == PromptAction.category,
              aps["sound"] as? String == "default",
              aps["thread-id"] as? String == "teacher-lesson:\(rawID)",
              let alert = aps["alert"] as? [String: Any],
              Set(alert.keys) == Set(["title", "body"]),
              alert["title"] is String, alert["body"] is String else { return nil }
        return PromptDestination(lessonID: id, action: action)
    }
}

/// Locator metadata only. Never persist a session, token, roster, feedback, or write.
public struct PendingRoute: Codable, Equatable {
    public let id: UUID
    public let lessonID: UUID
    public let receivedAt: Date
    public var action: PromptAction
    public var boundAccountID: UUID?
}

public protocol PendingRoutePersistence {
    func load() throws -> Data?
    /// Implement as an atomic replacement. A thrown write must not be reported as success.
    func save(_ data: Data) throws
}

public struct PromptAccount: Equatable {
    public enum Role: String { case teacher, admin, parent, other }
    public let id: UUID
    public let role: Role
    public let isActive: Bool
    public init(id: UUID, role: Role, isActive: Bool = true) {
        self.id = id; self.role = role; self.isActive = isActive
    }
    var eligible: Bool { isActive && (role == .teacher || role == .admin) }
}

public enum PromptAuthentication: Equatable {
    case restoring, signedOut, loadingProfile(UUID), signedIn(PromptAccount)
    var accountID: UUID? {
        switch self {
        case .loadingProfile(let id): return id
        case .signedIn(let account): return account.id
        default: return nil
        }
    }
}

public struct PromptContext: Equatable {
    public var authentication: PromptAuthentication
    public var teacherPromptsEnabled: Bool
    public var isUnlocked: Bool
    public init(authentication: PromptAuthentication = .restoring,
                teacherPromptsEnabled: Bool = false, isUnlocked: Bool = false) {
        self.authentication = authentication
        self.teacherPromptsEnabled = teacherPromptsEnabled
        self.isUnlocked = isUnlocked
    }
}

public struct PromptResolution: Equatable {
    public let id: UUID
    public let routeID: UUID
    public let lessonID: UUID
    public let accountID: UUID
}

public struct ReadyPrompt: Equatable {
    public let lessonID: UUID
    public let accountID: UUID
    /// This only requests a visible confirmation. It is never a queued RPC/write.
    public let needsSnoozeConfirmation: Bool
}

public enum PromptUnavailable: Equatable {
    case denied, network, expired, disabled, accountMismatch, persistence, invalidSavedRoute
}

public enum PromptRouterState: Equatable {
    case idle, awaitingSignIn, awaitingUnlock
    case resolving(PromptResolution)
    case ready(ReadyPrompt)
    case unavailable(PromptUnavailable)
}

public enum PromptResolutionOutcome { case authorized, denied, networkFailure, sessionExpired }

/// Synchronous state machine; call on one executor (MainActor in the iOS sketch).
/// The caller performs lesson_for_prompt and feeds back its result. Time is injected.
public final class PromptRouter {
    public static let timeToLive: TimeInterval = 24 * 60 * 60
    public private(set) var state: PromptRouterState = .idle
    public private(set) var context = PromptContext()
    public var pending: PendingRoute? { snapshot.pending }

    private struct Receipt: Codable {
        let responseID: String
        let action: PromptAction
        let receivedAt: Date
    }
    private struct Snapshot: Codable {
        var version = 1
        var pending: PendingRoute?
        var receipts: [Receipt] = []
    }
    private var snapshot = Snapshot()
    private let persistence: any PendingRoutePersistence
    private let parser: PromptParser
    private let makeID: () -> UUID

    public init(approvedHosts: Set<String>, persistence: any PendingRoutePersistence,
                now: Date, makeID: @escaping () -> UUID = { UUID() }) throws {
        self.parser = PromptParser(approvedHosts: approvedHosts)
        self.persistence = persistence
        self.makeID = makeID
        if let data = try persistence.load() {
            guard let restored = try? JSONDecoder().decode(Snapshot.self, from: data),
                  restored.version == 1 else {
                try persist(Snapshot())
                state = .unavailable(.invalidSavedRoute)
                return
            }
            snapshot = restored
        }
        // A relaunch cannot prove the old action's session is still live.
        snapshot.pending?.action = .takeAttendance
        snapshot.receipts = validReceipts(now: now)
        try persist(snapshot)
        try advance(now: now)
    }

    @discardableResult
    public func open(link: String, now: Date) throws -> Bool {
        guard let destination = parser.parse(link: link) else { return false }
        try receive(destination, responseID: nil, now: now)
        return true
    }

    @discardableResult
    public func open(userInfo: [AnyHashable: Any], actionIdentifier: String,
                     responseID: String, now: Date) throws -> Bool {
        guard !responseID.isEmpty, responseID.utf8.count <= 256,
              let destination = parser.parse(userInfo: userInfo, actionIdentifier: actionIdentifier) else { return false }
        let receipts = validReceipts(now: now)
        guard !receipts.contains(where: { $0.responseID == responseID && $0.action == destination.action }) else {
            return false
        }
        try receive(destination, responseID: responseID, now: now)
        return true
    }

    private func receive(_ destination: PromptDestination, responseID: String?, now: Date) throws {
        var next = snapshot
        next.pending = PendingRoute(id: makeID(), lessonID: destination.lessonID, receivedAt: now,
                                    action: destination.action, boundAccountID: context.authentication.accountID)
        next.receipts = validReceipts(now: now)
        if let responseID {
            next.receipts.append(Receipt(responseID: responseID, action: destination.action, receivedAt: now))
            next.receipts = Array(next.receipts.suffix(32))
        }
        state = .idle // Immediately invalidates a previous request or sensitive screen.
        try persist(next)
        try advance(now: now)
    }

    public func update(context newContext: PromptContext, now: Date) throws {
        if newContext != context {
            let oldID = context.authentication.accountID
            let newID = newContext.authentication.accountID
            var next = snapshot
            let hasLiveSession: Bool
            if case .signedIn = newContext.authentication { hasLiveSession = true }
            else { hasLiveSession = false }
            // Never carry an actor-bound snooze across logout, refresh, or account switch.
            if !hasLiveSession || (oldID != nil && oldID != newID)
                || (next.pending?.boundAccountID != nil && next.pending?.boundAccountID != newID) {
                next.pending?.action = .takeAttendance
            }
            context = newContext
            state = .idle // Host must clear its roster/draft and ignore stale async responses.
            try persist(next)
        }
        try advance(now: now)
    }

    /// Explicit retry after network/authorization failure; never consumes a denied route.
    public func retry(now: Date) throws {
        state = .idle
        try advance(now: now)
    }

    /// Call on foreground/time changes too, so a waiting link cannot outlive its TTL.
    public func refresh(now: Date) throws { try advance(now: now) }

    public func complete(_ request: PromptResolution, outcome: PromptResolutionOutcome, now: Date) throws {
        guard case .resolving(let current) = state, current == request,
              let route = pending, route.id == request.routeID else { return }
        guard isFresh(route.receivedAt, now: now) else { try expire(); return }
        switch outcome {
        case .authorized:
            var next = snapshot
            next.pending = nil
            // Consume only after successful RPC and successful local durable write.
            try persist(next)
            state = .ready(ReadyPrompt(lessonID: route.lessonID, accountID: request.accountID,
                                      needsSnoozeConfirmation: route.action == .snoozeTen))
        case .denied: state = .unavailable(.denied)
        case .networkFailure: state = .unavailable(.network)
        case .sessionExpired:
            var next = snapshot
            next.pending?.action = .takeAttendance
            state = .awaitingSignIn
            context.authentication = .signedOut
            try persist(next)
        }
    }

    public func discard() throws {
        var next = snapshot
        next.pending = nil
        state = .idle
        try persist(next)
    }

    private func advance(now: Date) throws {
        guard let route = pending else { return }
        guard isFresh(route.receivedAt, now: now) else { try expire(); return }
        guard case .signedIn(let account) = context.authentication else { state = .awaitingSignIn; return }
        guard context.teacherPromptsEnabled else { state = .unavailable(.disabled); return }
        guard account.eligible else { state = .unavailable(.denied); return }
        guard context.isUnlocked else { state = .awaitingUnlock; return }
        guard route.boundAccountID == nil || route.boundAccountID == account.id else {
            state = .unavailable(.accountMismatch); return
        }
        if case .resolving = state { return }
        if case .unavailable = state { return } // Wait for explicit retry or a changed gate.
        var next = snapshot
        next.pending?.boundAccountID = account.id
        try persist(next)
        state = .resolving(PromptResolution(id: makeID(), routeID: route.id,
                                           lessonID: route.lessonID, accountID: account.id))
    }

    private func expire() throws {
        var next = snapshot
        next.pending = nil
        state = .unavailable(.expired)
        try persist(next)
    }

    private func isFresh(_ date: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < Self.timeToLive
    }

    private func validReceipts(now: Date) -> [Receipt] {
        Array(snapshot.receipts.filter { isFresh($0.receivedAt, now: now) }.suffix(32))
    }

    private func persist(_ next: Snapshot) throws {
        do {
            try persistence.save(JSONEncoder().encode(next))
            snapshot = next
        } catch {
            state = .unavailable(.persistence)
            throw error // Host maps to PromptStrings.storageUnavailable, never prints data.
        }
    }
}

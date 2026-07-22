import Foundation
import SwiftUI
import UIKit
import MetricKit
import Supabase

/// Event type — mirrors the `app_events.event_type` CHECK (migration 031).
enum AnalyticsEventType: String {
    case screenView = "screen_view"
    case tap
    case error
    case crash
    case ops
    case latency
}

/// One `app_events` row. `properties` carries IDs/counts only — NEVER student
/// names (PDPA). Context fields (user/role/version/platform/device/session) are
/// stamped by `Analytics` at build time.
struct AppEvent: Encodable {
    let occurred_at: Date
    let user_id: String?
    let role: String?
    let platform: String
    let app_version: String?
    let session_id: String
    let event_type: String
    let name: String
    let properties: AnyJSON
    let device: String
}

/// Supabase-native, fail-silent product analytics + observability (migration 031).
///
/// - No-op unless the `analytics` feature flag is ON (loaded once at sign-in;
///   pre-flag events are dropped — acceptable).
/// - In-memory batch, flushed every 30s and when the app backgrounds.
/// - **Drop on failure** (`try?`): a failed insert discards the batch. There is
///   deliberately no second offline queue — attendance capture must never be
///   blocked or complicated by analytics.
@MainActor
final class Analytics: NSObject {
    static let shared = Analytics()

    /// Buffered events awaiting the next flush. Exposed for tests.
    private(set) var buffer: [AppEvent] = []

    /// Set once from `AuthManager` after the profile resolves.
    var role: String?

    private let db = SupabaseManager.shared.client
    private let sessionId = UUID().uuidString
    private let platform = "ios"
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private let device = UIDevice.current.model

    // Long offline stretches must not grow the buffer without bound; keep the
    // most recent events and shed the oldest.
    private let maxBuffered = 500

    private var flushTimer: Timer?
    private var started = false

    private var enabled: Bool { FeatureFlagStore.shared.isEnabled(.analytics) }

    // MARK: - Lifecycle

    /// Starts the flush timer, background-flush observer and MetricKit crash
    /// subscriber. Side-effect free until called (so tests can construct freely).
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)

        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }

        track(.ops, name: "app_launch", properties: ["cold": .bool(true)])
    }

    @objc private func handleBackground() {
        Task { @MainActor in await flush() }
    }

    // MARK: - Capture

    /// Public entry point — no-op while the flag is OFF.
    func track(_ type: AnalyticsEventType, name: String, properties: JSONObject = [:]) {
        guard enabled else { return }
        record(type, name: name, properties: properties)
    }

    /// Buffers an event unconditionally (no flag gate). The flag gate lives in
    /// `track`; `record` is the seam used by tests and by `track`.
    func record(_ type: AnalyticsEventType, name: String, properties: JSONObject = [:]) {
        let event = AppEvent(
            occurred_at: Date(),
            user_id: db.auth.currentSession?.user.id.uuidString,
            role: role,
            platform: platform,
            app_version: appVersion,
            session_id: sessionId,
            event_type: type.rawValue,
            name: name,
            properties: .object(properties),
            device: device
        )
        buffer.append(event)
        if buffer.count > maxBuffered {
            buffer.removeFirst(buffer.count - maxBuffered)
        }
    }

    /// Times an async op and emits `{name}` with `duration_ms` folded into
    /// `properties` (merged with `extra`). Fires only on success; a throw
    /// propagates without an event (the error funnel captures the failure).
    @discardableResult
    func time<T>(_ name: String, type: AnalyticsEventType = .latency,
                 extra: JSONObject = [:], _ op: () async throws -> T) async rethrows -> T {
        let start = Date()
        let result = try await op()
        var props = extra
        props["duration_ms"] = .integer(Int(Date().timeIntervalSince(start) * 1000))
        track(type, name: name, properties: props)
        return result
    }

    /// Elapsed milliseconds since `start`, for events that also carry counts and
    /// so can't use the `time` wrapper.
    static func ms(since start: Date) -> AnyJSON { .integer(Int(Date().timeIntervalSince(start) * 1000)) }

    // MARK: - Flush

    /// Sends the buffered batch. **Drops the batch on any failure** — the buffer
    /// is cleared before the await, so a throw simply discards those events.
    /// `sink` is injectable for tests; production uses the Supabase insert.
    func flush(using sink: ([AppEvent]) async throws -> Void) async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        try? await sink(batch)
    }

    func flush() async {
        await flush(using: { batch in
            struct Params: Encodable {
                let events: [AppEvent]
                enum CodingKeys: String, CodingKey { case events = "p_events" }
            }
            for start in stride(from: 0, to: batch.count, by: 100) {
                let end = min(start + 100, batch.count)
                try await self.db.rpc(
                    "submit_app_events",
                    params: Params(events: Array(batch[start..<end]))
                ).execute()
            }
        })
    }
}

// MARK: - MetricKit crash diagnostics (next-launch detection)

extension Analytics: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes: [(mechanism: String, reason: String)] = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map { d in
                (d.exceptionType.map { "exception:\($0)" } ?? "crash",
                 d.terminationReason ?? d.exceptionCode.map { "code:\($0)" } ?? "unknown")
            }
        }
        guard !crashes.isEmpty else { return }
        Task { @MainActor in
            for crash in crashes {
                track(.crash, name: "crash_detected",
                      properties: ["mechanism": .string(crash.mechanism), "reason": .string(crash.reason)])
            }
            await flush()
        }
    }
}

// MARK: - Screen-view modifier

extension View {
    /// One line per staff screen — emits a `screen_view` on appear.
    func analyticsScreen(_ name: String) -> some View {
        onAppear { Analytics.shared.track(.screenView, name: name) }
    }
}

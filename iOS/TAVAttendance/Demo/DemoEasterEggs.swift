import Foundation
import SwiftUI

/// Friendly surprises for a few familiar names on the demo roster. Kept in sync
/// with `web/lib/demo/easter-eggs.ts`.
struct DemoEasterEgg: Equatable, Identifiable {
    let name: String
    let emoji: String
    /// Shown when the student is signed in / marked present or late.
    let checkInMessage: String
    /// Shown when someone opens the student's profile.
    let profileMessage: String
    /// Tint for the celebration banner.
    let tint: Color

    var id: String { name }

    static let all: [DemoEasterEgg] = [
        DemoEasterEgg(
            name: "Lauren Tan",
            emoji: "🌟",
            checkInMessage: "Lauren Tan is here! Perfect attendance streak continues.",
            profileMessage: "Fun fact: Lauren hasn't missed a single class all year.",
            tint: .yellow),
        DemoEasterEgg(
            name: "Brian Chew",
            emoji: "🏀",
            checkInMessage: "Brian Chew checks in. Nothing but net!",
            profileMessage: "Fun fact: Brian once explained fractions using basketball stats. It worked.",
            tint: .orange),
        DemoEasterEgg(
            name: "Agrim Singh",
            emoji: "🚀",
            checkInMessage: "Agrim Singh has landed. Mission control: all systems go!",
            profileMessage: "Fun fact: Agrim asks the best \"but why?\" questions in class.",
            tint: .indigo),
        DemoEasterEgg(
            name: "Nick Chan",
            emoji: "🎉",
            checkInMessage: "Nick Chan is in the house! High-fives all round.",
            profileMessage: "Fun fact: Nick holds the centre record for most high-fives in one evening.",
            tint: .pink),
    ]

    static func forStudent(named fullName: String) -> DemoEasterEgg? {
        let key = fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.name.lowercased() == key }
    }
}

enum DemoEasterEggMoment: Equatable, Sendable {
    case checkIn
    case profile
}

/// Publishes Easter egg moments to the demo overlay. Only used in demo mode.
@MainActor
final class DemoEasterEggCenter: ObservableObject {
    typealias Moment = DemoEasterEggMoment

    struct Event: Equatable, Identifiable {
        let egg: DemoEasterEgg
        let moment: Moment
        let id = UUID()

        var message: String {
            moment == .checkIn ? egg.checkInMessage : egg.profileMessage
        }
    }

    static let shared = DemoEasterEggCenter()

    @Published private(set) var current: Event?
    private var lastShown: [String: Date] = [:]
    private var dismissTask: Task<Void, Never>?

    func trigger(_ egg: DemoEasterEgg, moment: Moment) {
        guard DemoMode.isActive else { return }
        // A student in two classes is marked twice by the kiosk; celebrate once.
        let key = "\(egg.name)-\(moment)"
        if let last = lastShown[key], Date().timeIntervalSince(last) < 3 { return }
        lastShown[key] = Date()
        let event = Event(egg: egg, moment: moment)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { current = event }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: moment == .checkIn ? 3_500_000_000 : 4_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.current?.id == event.id else { return }
                withAnimation(.easeOut(duration: 0.3)) { self.current = nil }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) { current = nil }
    }

    func reset() {
        dismissTask?.cancel()
        current = nil
        lastShown = [:]
    }

    /// Called off the main actor by `DemoStore`.
    nonisolated static func post(studentName: String, moment: DemoEasterEggMoment) {
        guard let egg = DemoEasterEgg.forStudent(named: studentName) else { return }
        Task { @MainActor in
            DemoEasterEggCenter.shared.trigger(egg, moment: moment)
        }
    }
}

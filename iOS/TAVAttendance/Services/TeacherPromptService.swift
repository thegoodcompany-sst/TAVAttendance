import Foundation
import PromptRouter

@MainActor
protocol TeacherPromptServing {
    var accountID: UUID { get }
    func lessons() async throws -> TeacherLessons
    func lesson(_ id: UUID) async throws -> TeacherLessonProjection
    func allPresent(_ mutation: TeacherRegisterMutation) async throws
    @discardableResult func mark(_ mutation: TeacherMark) async throws -> TeacherMarkReceipt
    func feedback(_ mutation: TeacherFeedbackMutation) async throws
    func submit(_ mutation: TeacherSubmitMutation) async throws
    func confirmAllPresentAndSubmit(_ mutation: TeacherSubmitMutation) async throws
    func snooze(_ lessonID: UUID, mutationID: UUID) async throws
}

/// The same account-bound transport serves lessons and the package device lifecycle.
@MainActor
final class TeacherPromptRPC: TeacherSessionRPC {
    let accountID: UUID
    private let session: ConvexTeacherSession
    private let generation: UUID
    private let allowed: () -> Bool
    private let masterEnabled: () -> Bool

    init(accountID: UUID, session: ConvexTeacherSession, allowed: @escaping () -> Bool,
         masterEnabled: @escaping () -> Bool) {
        self.accountID = accountID
        self.session = session
        self.generation = session.generation
        self.allowed = allowed
        self.masterEnabled = masterEnabled
    }

    func call<Parameters: Encodable, Response: Decodable>(
        _ name: String, parameters: Parameters, returning: Response.Type
    ) async throws -> Response {
        guard masterEnabled(), !DemoMode.isActive else { throw TeacherPromptError.disabled }
        guard session.accountID == accountID else { throw TeacherPromptError.sessionExpired }
        let kind: String
        let module: String
        switch name {
        case "my_lessons_today", "lesson_for_prompt":
            kind = "query"; module = "teacher"
        case "register_device", "unregister_device":
            kind = "mutation"; module = "devices"
        case "mark_attendance", "mark_all_present", "save_feedback", "submit_lesson",
             "confirm_all_present_and_submit", "snooze_prompt":
            kind = "mutation"; module = "teacher"
        default: throw TeacherPromptError.invalid
        }
        return try await session.call(kind, "\(module):\(name)", parameters, generation: generation) {
            self.masterEnabled() && !DemoMode.isActive && (name == "unregister_device" || self.allowed())
        }
    }
}

@MainActor
final class TeacherPromptService: TeacherPromptServing {
    private let rpc: any TeacherSessionRPC
    private let allowed: () -> Bool
    var accountID: UUID { rpc.accountID }
    init(rpc: any TeacherSessionRPC, allowed: @escaping () -> Bool) {
        self.rpc = rpc; self.allowed = allowed
    }
    private func call<P: Encodable, R: Decodable>(_ name: String, _ parameters: P, _ type: R.Type) async throws -> R {
        guard allowed() else { throw TeacherPromptError.disabled }
        return try await rpc.call(name, parameters: parameters, returning: type)
    }
    func lessons() async throws -> TeacherLessons {
        struct Empty: Encodable {}
        return try await call("my_lessons_today", Empty(), TeacherLessons.self)
    }
    func lesson(_ id: UUID) async throws -> TeacherLessonProjection {
        struct Parameters: Encodable { let p_lesson_id: UUID }
        return try await call("lesson_for_prompt", Parameters(p_lesson_id: id), TeacherLessonProjection.self)
    }
    func allPresent(_ mutation: TeacherRegisterMutation) async throws {
        _ = try await call("mark_all_present", mutation, TeacherAllPresentReceipt.self)
    }
    @discardableResult func mark(_ mutation: TeacherMark) async throws -> TeacherMarkReceipt {
        try await call("mark_attendance", mutation, TeacherMarkReceipt.self)
    }
    func feedback(_ mutation: TeacherFeedbackMutation) async throws {
        _ = try await call("save_feedback", mutation, TeacherFeedbackReceipt.self)
    }
    func submit(_ mutation: TeacherSubmitMutation) async throws {
        _ = try await call("submit_lesson", mutation, TeacherSubmitReceipt.self)
    }
    func confirmAllPresentAndSubmit(_ mutation: TeacherSubmitMutation) async throws {
        _ = try await call("confirm_all_present_and_submit", mutation, TeacherSubmitReceipt.self)
    }
    func snooze(_ lessonID: UUID, mutationID: UUID) async throws {
        struct Parameters: Encodable { let p_lesson_id: UUID; let p_minutes: Int; let p_mutation_id: UUID }
        _ = try await call("snooze_prompt", Parameters(p_lesson_id: lessonID, p_minutes: 10,
                                                      p_mutation_id: mutationID), TeacherSnoozeReceipt.self)
    }
}

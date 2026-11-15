import Foundation
import Supabase
import PromptRouter

@MainActor
protocol TeacherPromptServing {
    var accountID: UUID { get }
    func lessons() async throws -> TeacherLessons
    func lesson(_ id: UUID) async throws -> TeacherLessonProjection
    func allPresent(_ mutation: TeacherRegisterMutation) async throws
    func mark(_ mutation: TeacherMark) async throws
    func feedback(_ mutation: TeacherFeedbackMutation) async throws
    func submit(_ mutation: TeacherSubmitMutation) async throws
    func snooze(_ lessonID: UUID, mutationID: UUID) async throws
}

/// The same account-bound transport serves lessons and the package device lifecycle.
@MainActor
final class TeacherPromptRPC: TeacherSessionRPC {
    let accountID: UUID
    private let client: PostgrestClient
    private let refreshedClient: (() -> PostgrestClient?)?
    private let allowed: () -> Bool
    private let masterEnabled: () -> Bool

    init(accountID: UUID, client: PostgrestClient, allowed: @escaping () -> Bool,
         masterEnabled: @escaping () -> Bool, refreshedClient: (() -> PostgrestClient?)? = nil) {
        self.accountID = accountID; self.client = client
        self.allowed = allowed; self.masterEnabled = masterEnabled; self.refreshedClient = refreshedClient
    }
    func call<Parameters: Encodable, Response: Decodable>(
        _ name: String, parameters: Parameters, returning: Response.Type
    ) async throws -> Response {
        guard masterEnabled(), !DemoMode.isActive else { throw TeacherPromptError.disabled }
        // Owner-bound cleanup must still work after runtime flag/profile removal.
        guard name == "unregister_device" || allowed() else { throw TeacherPromptError.disabled }
        try Task.checkCancellation()
        do {
            // Refresh only this same account; the request client itself never changes identity.
            let boundClient = refreshedClient?() ?? client
            return try await boundClient.rpc(name, params: parameters).execute().value
        } catch let error as PostgrestError {
            if error.code == "PGRST301" || error.code == "PGRST303" { throw TeacherPromptError.sessionExpired }
            throw TeacherPromptError(rawValue: error.message) ?? .network
        } catch is CancellationError { throw CancellationError() }
        catch { throw TeacherPromptError.network }
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
        _ = try await call("mark_all_present", mutation, TeacherMutationReceipt.self)
    }
    func mark(_ mutation: TeacherMark) async throws {
        _ = try await call("mark_attendance", mutation, TeacherMutationReceipt.self)
    }
    func feedback(_ mutation: TeacherFeedbackMutation) async throws {
        _ = try await call("save_feedback", mutation, TeacherMutationReceipt.self)
    }
    func submit(_ mutation: TeacherSubmitMutation) async throws {
        _ = try await call("submit_lesson", mutation, TeacherMutationReceipt.self)
    }
    func snooze(_ lessonID: UUID, mutationID: UUID) async throws {
        struct Parameters: Encodable { let p_lesson_id: UUID; let p_minutes: Int; let p_mutation_id: UUID }
        _ = try await call("snooze_prompt", Parameters(p_lesson_id: lessonID, p_minutes: 10,
                                                      p_mutation_id: mutationID), TeacherMutationReceipt.self)
    }
}

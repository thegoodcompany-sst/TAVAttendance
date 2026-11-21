import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PromptRouter

private struct ConvexRequest<Args: Encodable>: Encodable {
    let path: String
    let format = "json"
    let args: Args
}

private struct ConvexStatus: Decodable {
    let status: String
    let errorData: String?
    let errorMessage: String?
}

private struct ConvexResult<Value: Decodable>: Decodable { let value: Value }
private struct ConvexEmpty: Codable {}

/// The token pair is one Keychain item scoped to this deployment. A new login,
/// even by the same person, invalidates requests and refreshes from the old session.
@MainActor
final class ConvexTeacherSession {
    private struct Tokens: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
    }
    private struct SignInResult: Decodable { let status: String; let tokens: Tokens? }
    private struct RefreshResult: Decodable { let kind: String; let tokens: Tokens? }
    private let url: URL?
    private let http: URLSession
    private let storage: any PendingRoutePersistence
    private var tokens: Tokens?
    private var refresh: Task<Void, Error>?
    private(set) var generation = UUID()
    private(set) var accountID: UUID?

    init(url: URL?, http: URLSession, storage: any PendingRoutePersistence) {
        self.url = url
        self.http = http
        self.storage = storage
    }

    func restore() throws -> Bool {
        guard let data = try storage.load(), !data.isEmpty else { return false }
        // A v1 pair uses "token" and cannot authenticate against the v2 issuer.
        guard let stored = try? JSONDecoder().decode(Tokens.self, from: data) else {
            try clear()
            return false
        }
        tokens = stored
        return true
    }

    private func invalidate() {
        generation = UUID()
        refresh?.cancel()
        refresh = nil
        tokens = nil
        accountID = nil
    }

    private func clear() throws {
        invalidate()
        try storage.save(Data())
    }

    func enterDemo() throws {
        if tokens != nil { try clear() }
        else { invalidate() } // Cancel any sign-in still waiting for its first token pair.
    }

    func signIn(email: String, password: String) async throws {
        try clear()
        let started = generation
        let result: SignInResult = try await post("mutation", "auth:signIn",
            ["email": email, "password": password], bearer: nil)
        guard generation == started else { throw CancellationError() }
        if result.status == "error" { throw TeacherPromptError.sessionExpired }
        guard result.status == "complete" else { throw TeacherPromptError.network }
        try accept(result.tokens, generation: started)
    }

    func profile() async throws -> TeacherProfile {
        let started = generation
        let profile: TeacherProfile = try await call("query", "teacher:my_profile", ConvexEmpty(),
                                                     generation: started)
        guard generation == started else { throw CancellationError() }
        guard accountID == nil || accountID == profile.id else { throw TeacherPromptError.sessionExpired }
        accountID = profile.id
        return profile
    }

    func signOut() async throws {
        let current = tokens
        let localRemoval = Result { try clear() }
        if let current {
            let _: ConvexEmpty? = try await post("mutation", "auth:signOut",
                ["refreshToken": current.refreshToken], bearer: nil)
        }
        try localRemoval.get()
    }

    private func accept(_ tokensToSave: Tokens?, generation started: UUID) throws {
        guard started == generation else { throw CancellationError() }
        guard let pair = tokensToSave, !pair.accessToken.isEmpty, !pair.refreshToken.isEmpty else {
            throw TeacherPromptError.network
        }
        try storage.save(JSONEncoder().encode(pair))
        tokens = pair
    }

    private func refresh(rejected: Tokens, generation started: UUID) async throws {
        guard generation == started else { throw CancellationError() }
        guard tokens == rejected else { return } // Another request already rotated the pair.
        if let refresh { try await refresh.value; return }
        let task = Task {
            let result: RefreshResult = try await post("mutation", "auth:refreshSession",
                                                ["refreshToken": rejected.refreshToken], bearer: nil)
            guard generation == started else { throw CancellationError() }
            if result.kind == "noSession" {
                // Keep this login generation until AuthManager handles expiry.
                // Changing it here would discard the sign-out as a stale response.
                tokens = nil
                accountID = nil
                try storage.save(Data())
                throw TeacherPromptError.sessionExpired
            }
            guard result.kind == "rotated" else { throw TeacherPromptError.network }
            try accept(result.tokens, generation: started)
        }
        refresh = task
        defer { if generation == started { refresh = nil } }
        try await task.value
    }

    func call<Args: Encodable, Value: Decodable>(
        _ kind: String, _ path: String, _ args: Args, generation started: UUID,
        allowed: () -> Bool = { true }
    ) async throws -> Value {
        func send(_ bearer: String) async throws -> Value {
            guard started == generation else { throw CancellationError() }
            guard allowed() else { throw TeacherPromptError.disabled }
            let result: Value = try await post(kind, path, args, bearer: bearer)
            guard started == generation else { throw CancellationError() }
            guard tokens != nil else { throw TeacherPromptError.sessionExpired }
            return result
        }
        guard started == generation, let current = tokens else { throw TeacherPromptError.sessionExpired }
        do { return try await send(current.accessToken) }
        catch TeacherPromptError.sessionExpired {
            try await refresh(rejected: current, generation: started)
            guard started == generation else { throw CancellationError() }
            guard let rotated = tokens else { throw TeacherPromptError.sessionExpired }
            return try await send(rotated.accessToken)
        }
    }

    private func post<Args: Encodable, Value: Decodable>(
        _ kind: String, _ path: String, _ args: Args, bearer: String?
    ) async throws -> Value {
        guard let url else { throw TeacherPromptError.network }
        try Task.checkCancellation()
        var request = URLRequest(url: url.appendingPathComponent("api").appendingPathComponent(kind))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        do {
            request.httpBody = try JSONEncoder().encode(ConvexRequest(path: path, args: args))
            let (data, response) = try await http.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw TeacherPromptError.network }
            if response.statusCode == 401 { throw TeacherPromptError.sessionExpired }
            let decoder = JSONDecoder()
            guard let status = try? decoder.decode(ConvexStatus.self, from: data) else {
                throw response.statusCode == 400 ? TeacherPromptError.invalid : .network
            }
            if status.status == "error" {
                if let code = status.errorData, let error = TeacherPromptError(rawValue: code) { throw error }
                let message = status.errorMessage ?? ""
                if response.statusCode == 400 || message.contains("ArgumentValidationError") { throw TeacherPromptError.invalid }
                throw TeacherPromptError.network
            }
            guard (200..<300).contains(response.statusCode), status.status == "success" else {
                throw TeacherPromptError.network
            }
            return try decoder.decode(ConvexResult<Value>.self, from: data).value
        } catch let error as TeacherPromptError { throw error }
        catch {
            try Task.checkCancellation()
            throw TeacherPromptError.network
        }
    }
}

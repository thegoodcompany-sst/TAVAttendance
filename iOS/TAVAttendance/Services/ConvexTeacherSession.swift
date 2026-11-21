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
        let token: String
        let refreshToken: String
    }
    private struct Issued: Decodable { let tokens: Tokens? }
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
        tokens = try JSONDecoder().decode(Tokens.self, from: data)
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
        struct Args: Encodable {
            let provider = "password"
            let params: [String: String]
        }
        try clear()
        let started = generation
        let args = Args(params: ["flow": "signIn", "email": email, "password": password])
        let issued: Issued = try await post("action", "auth:signIn", args, bearer: nil, passwordSignIn: true)
        try accept(issued, generation: started)
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
        let started = generation
        do {
            if tokens != nil {
                let _: ConvexEmpty? = try await call("action", "auth:signOut", ConvexEmpty(), generation: started)
            }
        } catch {
            if started == generation { try clear() }
            throw error
        }
        if started == generation { try clear() }
    }

    private func accept(_ issued: Issued, generation started: UUID) throws {
        guard started == generation else { throw CancellationError() }
        guard let pair = issued.tokens, !pair.token.isEmpty, !pair.refreshToken.isEmpty else {
            throw TeacherPromptError.sessionExpired
        }
        try storage.save(JSONEncoder().encode(pair))
        tokens = pair
    }

    private func refresh(rejected: Tokens, generation started: UUID) async throws {
        guard generation == started else { throw CancellationError() }
        guard tokens == rejected else { return } // Another request already rotated the pair.
        if let refresh { try await refresh.value; return }
        let task = Task {
            let issued: Issued = try await post("action", "auth:signIn",
                                                ["refreshToken": rejected.refreshToken], bearer: nil)
            try accept(issued, generation: started)
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
            return result
        }
        guard started == generation, let current = tokens else { throw TeacherPromptError.sessionExpired }
        do { return try await send(current.token) }
        catch TeacherPromptError.sessionExpired {
            try await refresh(rejected: current, generation: started)
            guard started == generation, let rotated = tokens else { throw CancellationError() }
            return try await send(rotated.token)
        }
    }

    private func post<Args: Encodable, Value: Decodable>(
        _ kind: String, _ path: String, _ args: Args, bearer: String?, passwordSignIn: Bool = false
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
                // Hosted Auth can redact an ordinary Password provider rejection to "Server Error".
                if passwordSignIn, response.statusCode == 560, message.hasSuffix("Server Error") {
                    throw TeacherPromptError.sessionExpired
                }
                if path == "auth:signIn", ["Invalid credentials", "InvalidAccountId", "InvalidSecret", "TooManyFailedAttempts",
                     "Can't parse refresh token"].contains(where: message.contains) {
                    throw TeacherPromptError.sessionExpired
                }
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

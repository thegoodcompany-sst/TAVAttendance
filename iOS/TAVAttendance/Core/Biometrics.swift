import LocalAuthentication

enum Biometrics {
    /// "Face ID" / "Touch ID", or nil when the policy can't be evaluated at all.
    static func biometryName(policy: LAPolicy = .deviceOwnerAuthentication) -> String? {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(policy, error: nil) else { return nil }
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return policy == .deviceOwnerAuthentication ? "Passcode" : nil
        }
    }

    static func authenticate(reason: String, policy: LAPolicy = .deviceOwnerAuthentication) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(policy, error: nil) else { return false }
        return (try? await ctx.evaluatePolicy(policy, localizedReason: reason)) ?? false
    }
}

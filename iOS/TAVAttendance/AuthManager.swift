import SwiftUI

enum UserRole: String, Codable {
    case tutor
    case admin
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let roles: [UserRole]
}

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var profile: UserProfile?
    @Published var isLoading = true
    @Published var selectedRole: UserRole = .admin
    
    private init() {
        // Check for existing session
        Task {
            await checkSession()
        }
    }
    
    func checkSession() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implement actual authentication check
        // For now, this will just check if there's a stored session
        
        // Simulate network delay
        try? await Task.sleep(for: .milliseconds(500))
        
        // Check UserDefaults or Keychain for stored credentials
        if let profileData = UserDefaults.standard.data(forKey: "userProfile"),
           let savedProfile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            profile = savedProfile
            
            // Restore selected role if available
            if let roleString = UserDefaults.standard.string(forKey: "selectedRole"),
               let role = UserRole(rawValue: roleString) {
                selectedRole = role
            }
        }
    }
    
    func login(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implement actual API call to your backend
        // This is a placeholder implementation
        
        // Simulate network delay
        try await Task.sleep(for: .seconds(1))
        
        // Mock successful login
        let mockProfile = UserProfile(
            id: UUID().uuidString,
            email: email,
            name: "Mock User",
            roles: [.admin, .tutor]
        )
        
        profile = mockProfile
        selectedRole = mockProfile.roles.first ?? .admin
        
        // Save to UserDefaults (in production, use Keychain for sensitive data)
        if let encoded = try? JSONEncoder().encode(mockProfile) {
            UserDefaults.standard.set(encoded, forKey: "userProfile")
        }
        UserDefaults.standard.set(selectedRole.rawValue, forKey: "selectedRole")
    }
    
    func logout() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: "userProfile")
        UserDefaults.standard.removeObject(forKey: "selectedRole")
    }
    
    func switchRole(to role: UserRole) {
        guard profile?.roles.contains(role) == true else { return }
        selectedRole = role
        UserDefaults.standard.set(role.rawValue, forKey: "selectedRole")
    }
}

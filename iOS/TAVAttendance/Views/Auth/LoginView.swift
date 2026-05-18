import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager

    @State private var email    = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRole: UserRole?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("TAVA Attendance")
                    .font(.largeTitle).bold()

                // Role Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Role")
                        .font(.headline)
                        .padding(.leading)

                    HStack(spacing: 12) {
                        ForEach([UserRole.tutor, UserRole.admin, UserRole.parent], id: \.self) { role in
                            Button(action: { selectedRole = role }) {
                                VStack(spacing: 8) {
                                    Image(systemName: roleIcon(for: role))
                                        .font(.title2)
                                    Text(roleLabel(for: role))
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                                .foregroundStyle(selectedRole == role ? .white : .primary)
                                .background(selectedRole == role ? Color.blue : Color(.systemGray5))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                if let message = errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: signIn) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isLoading || selectedRole == nil)
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarHidden(true)
        }
    }

    private func signIn() {
        isLoading    = true
        errorMessage = nil
        Task {
            do {
                try await auth.signIn(email: email, password: password, selectedRole: selectedRole)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func roleIcon(for role: UserRole) -> String {
        switch role {
        case .tutor: return "person.fill"
        case .admin: return "shield.fill"
        case .parent: return "family.fill"
        }
    }

    private func roleLabel(for role: UserRole) -> String {
        switch role {
        case .tutor: return "Attendance Taker"
        case .admin: return "Admin"
        case .parent: return "Parent"
        }
    }
}

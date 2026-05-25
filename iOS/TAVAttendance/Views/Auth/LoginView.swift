import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Text("TAVA")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Attendance")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }

                    // Form card
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textContentType(.emailAddress)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            Button(action: signIn) {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .cornerRadius(10)
                            }
                            .disabled(email.isEmpty || password.isEmpty)
                        }
                    }
                    .padding(28)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

    private func signIn() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

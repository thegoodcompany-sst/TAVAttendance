import SwiftUI

/// Floating "Demo" badge with reset/exit controls.
/// Only rendered while on-device demo mode is active.
struct DemoModeOverlay: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var confirmingReset = false

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                HStack {
                    badge
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.bottom, 64)
            }
        }
        .confirmationDialog(
            "Reset demo data?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset demo data", role: .destructive) {
                authManager.resetDemoData()
            }
        } message: {
            Text("Every change made in this demo is thrown away and the sample data is restored. Nothing on the real server is affected.")
        }
    }

    private var badge: some View {
        Menu {
            Section("On-device demo · nothing is sent to the server") {
                Button {
                    confirmingReset = true
                } label: {
                    Label("Reset demo data", systemImage: "arrow.counterclockwise")
                }
                Button(role: .destructive) {
                    Task { try? await authManager.signOut() }
                } label: {
                    Label("Exit demo", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Label("Demo", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.purple.opacity(0.9)))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel("Demo mode. Opens reset and exit options.")
        .accessibilityIdentifier("demoModeBadge")
    }
}

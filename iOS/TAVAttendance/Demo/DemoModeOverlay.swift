import SwiftUI

/// Floating "Demo" badge (with reset/exit controls) plus the Easter egg banner.
/// Only rendered while on-device demo mode is active.
struct DemoModeOverlay: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var eggs = DemoEasterEggCenter.shared
    @State private var confirmingReset = false

    var body: some View {
        ZStack {
            if let event = eggs.current {
                VStack {
                    DemoEasterEggBanner(event: event)
                        .onTapGesture { eggs.dismiss() }
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }

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

private struct DemoEasterEggBanner: View {
    let event: DemoEasterEggCenter.Event

    var body: some View {
        HStack(spacing: 14) {
            Text(event.egg.emoji)
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.egg.name)
                    .font(.headline)
                Text(event.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(event.egg.tint.opacity(0.6), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

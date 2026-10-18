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
                if event.moment == .checkIn {
                    DemoConfettiView(seed: event.id.hashValue)
                        .id(event.id)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
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

/// Lightweight confetti burst: coloured pieces fall once from the top edge.
private struct DemoConfettiView: View {
    let seed: Int
    @State private var falling = false

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let duration: Double
        let spin: Double
        let size: CGFloat
        let color: Color
    }

    private var pieces: [Piece] {
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(seed)))
        let colors: [Color] = [.pink, .orange, .yellow, .green, .blue, .purple, .red, .mint]
        return (0..<48).map { i in
            Piece(
                id: i,
                x: CGFloat.random(in: 0...1, using: &generator),
                delay: Double.random(in: 0...0.6, using: &generator),
                duration: Double.random(in: 1.6...2.8, using: &generator),
                spin: Double.random(in: 180...720, using: &generator),
                size: CGFloat.random(in: 7...13, using: &generator),
                color: colors[i % colors.count])
        }
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 0.55)
                    .rotationEffect(.degrees(falling ? piece.spin : 0))
                    .position(
                        x: piece.x * geo.size.width,
                        y: falling ? geo.size.height + 40 : -20)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: falling)
            }
        }
        .ignoresSafeArea()
        .onAppear { falling = true }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}

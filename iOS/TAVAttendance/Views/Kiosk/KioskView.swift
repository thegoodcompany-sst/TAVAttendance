import SwiftUI

// Single-class kiosk — kept for direct deep-links but the main entry
// point is now GlobalKioskView (Sign-In tab).
struct KioskView: View {
    let session: Session
    let tavClass: TAVClass

    @Environment(\.dismiss) private var dismiss

    @State private var roster: [RosterEntry] = []
    @State private var isLoading = true
    @State private var pendingIds: Set<UUID> = []
    @State private var showExitConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 16)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                kioskHeader

                if isLoading {
                    Spacer()
                    ProgressView("Loading class list…").controlSize(.large)
                    Spacer()
                } else if roster.isEmpty {
                    Spacer()
                    ContentUnavailableView("No Students", systemImage: "person.3",
                                          description: Text("No students are enrolled in this class yet."))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(roster) { entry in
                                StudentSignInCard(
                                    entry: entry,
                                    isPending: pendingIds.contains(entry.studentId)
                                ) { Task { await markPresent(entry: entry) } }
                            }
                        }
                        .padding(24)
                    }
                }
            }

            Button { showExitConfirm = true } label: {
                Label("Exit", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .task { await loadRoster() }
        .confirmationDialog("Exit Sign-In Mode?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Exit", role: .destructive) { dismiss() }
            Button("Stay in Sign-In Mode", role: .cancel) {}
        } message: {
            Text("Students won't be able to sign in after you exit.")
        }
    }

    private var presentCount: Int { roster.filter { $0.status == .present }.count }

    private var kioskHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign In").font(.largeTitle.bold())
                Text(tavClass.name).font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(presentCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("/ \(roster.count) present").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background(.bar)
    }

    private func loadRoster() async {
        isLoading = true
        defer { isLoading = false }
        do { roster = try await AttendanceService.shared.fetchRoster(sessionId: session.id) } catch {}
    }

    private func markPresent(entry: RosterEntry) async {
        guard entry.status != .present, !pendingIds.contains(entry.studentId) else { return }
        pendingIds.insert(entry.studentId)
        do {
            try await AttendanceService.shared.markAttendance(
                sessionId: session.id, studentId: entry.studentId, status: .present)
            if let idx = roster.firstIndex(where: { $0.studentId == entry.studentId }) {
                roster[idx].status = .present
            }
        } catch {}
        pendingIds.remove(entry.studentId)
    }
}

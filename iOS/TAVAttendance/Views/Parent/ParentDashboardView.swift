import SwiftUI

/// PROD-01 — parent-facing home. Gated by the `parent_portal` feature flag:
/// until an admin enables it, parents see a "being prepared" placeholder instead
/// of falling through to the tutor class list. When enabled, a parent sees their
/// linked children and can open each child's attendance history.
///
/// No new RLS is needed: `students: parent can read own children` and
/// `attendance_records: parent reads own children` already exist (002_rls.sql),
/// so `fetchAllStudents()` returns only this parent's children.
struct ParentDashboardView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var featureFlags: FeatureFlagStore

    @State private var children: [Student] = []
    @State private var isLoading = true
    @State private var selectedChild: Student?

    var body: some View {
        NavigationStack {
            Group {
                if !featureFlags.isEnabled(.parentPortal) {
                    placeholder
                } else if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    childList
                }
            }
            .navigationTitle("My Children")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { Task { try? await authManager.signOut() } }
                }
            }
            .sheet(item: $selectedChild) { child in
                StudentProfileView(studentId: child.id, fullName: child.fullName)
                    .environmentObject(authManager)
            }
        }
        .task {
            // Only hit the network if the portal is live.
            if featureFlags.isEnabled(.parentPortal) { await loadChildren() }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "hourglass")
        } description: {
            Text("Your child's attendance history is being prepared. You'll be able to view it here soon.")
        }
    }

    private var childList: some View {
        Group {
            if children.isEmpty {
                ContentUnavailableView(
                    "No Children Linked",
                    systemImage: "person.2.slash",
                    description: Text("No students are linked to your account yet. Please contact the centre.")
                )
            } else {
                List(children) { child in
                    Button {
                        selectedChild = child
                    } label: {
                        HStack {
                            Text(child.fullName)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private func loadChildren() async {
        isLoading = true
        children = (try? await AttendanceService.shared.fetchAllStudents()) ?? []
        isLoading = false
    }
}

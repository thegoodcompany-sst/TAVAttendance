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
    @State private var loadFailed = false
    @State private var selectedChild: Student?
    @State private var pendingDismissals: [Dismissal] = []
    @State private var error: AppError?
    @AppStorage("biometricUnlockEnabled") private var biometricUnlockEnabled = false

    var body: some View {
        NavigationStack {
            Group {
                if !featureFlags.isEnabled(.parentPortal) {
                    placeholder
                } else if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loadFailed {
                    loadError
                } else {
                    childList
                }
            }
            .navigationTitle("My Children")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // ponytail: duplicated toggle (see ClassListView), extract if a third role appears
                        if let name = Biometrics.biometryName() {
                            Button {
                                Task {
                                    if biometricUnlockEnabled {
                                        biometricUnlockEnabled = false
                                    } else if await Biometrics.authenticate(reason: "Enable \(name) unlock") {
                                        biometricUnlockEnabled = true
                                    }
                                }
                            } label: {
                                Label("Require \(name) to Open",
                                      systemImage: biometricUnlockEnabled ? "checkmark" : "faceid")
                            }
                            Divider()
                        }
                        Button(role: .destructive) {
                            Task { try? await authManager.signOut() }
                        } label: {
                            Text("Sign Out")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .sheet(item: $selectedChild) { child in
                StudentProfileView(studentId: child.id, fullName: child.fullName, isParentMode: true)
                    .environmentObject(authManager)
            }
            .errorAlert(error: $error)
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

    // A load failure is distinct from "no children linked" — an empty list because the
    // request threw would otherwise read as "you have no children", hiding the error.
    private var loadError: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text("We couldn't load your children's information. Please check your connection and try again.")
        } actions: {
            Button("Retry") { Task { await loadChildren() } }
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
                List {
                    ForEach(pendingDismissals) { dismissal in
                        safelyHomeCard(dismissal)
                    }
                    ForEach(children) { child in
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
    }

    private func safelyHomeCard(_ dismissal: Dismissal) -> some View {
        let name = children.first { $0.id == dismissal.studentId }?.fullName ?? String(localized: "Your child")
        return VStack(alignment: .leading, spacing: 12) {
            if let at = dismissal.dismissedAt {
                Text("\(name) was dismissed at \(at.formatted(date: .omitted, time: .shortened)).")
            } else {
                Text("\(name) was dismissed today.")
            }
            Button("Mark Safely Home") {
                Task { await markSafelyHome(dismissal) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.accentColor.opacity(0.1))
    }

    private func markSafelyHome(_ dismissal: Dismissal) async {
        do {
            try await AttendanceService.shared.markSafelyHome(dismissalId: dismissal.id)
            pendingDismissals.removeAll { $0.id == dismissal.id }
        } catch {
            self.error = AppError("Couldn't confirm safely home. Please try again.", underlyingError: error)
        }
    }

    private func loadChildren() async {
        isLoading = true
        loadFailed = false
        do {
            children = try await AttendanceService.shared.fetchAllStudents()
        } catch {
            loadFailed = true
        }
        // Safely-home is best-effort decoration; a failure here must not hide the children list.
        pendingDismissals = AttendanceService.awaitingSafelyHome(
            (try? await AttendanceService.shared.fetchTodayDismissals()) ?? [])
        isLoading = false
    }
}

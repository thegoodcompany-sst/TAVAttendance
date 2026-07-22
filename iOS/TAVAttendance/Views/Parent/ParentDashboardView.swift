import SwiftUI

enum ParentDismissalVisibility {
    static func visible(pushNotificationsEnabled: Bool, dismissals: [Dismissal]) -> [Dismissal] {
        pushNotificationsEnabled ? AttendanceService.awaitingSafelyHome(dismissals) : []
    }
}

/// PROD-01 — parent-facing home. Gated by the `parent_portal` feature flag:
/// until an admin enables it, parents see a "being prepared" placeholder instead
/// of falling through to the tutor class list. When enabled, a parent sees their
/// linked children and can open each child's attendance history.
///
/// Migration 038 removes direct parent access to staff tables and exposes only
/// explicit safe-column RPCs for this surface.
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
        .task(id: dashboardFeatureState) {
            // Re-evaluate when either flag changes. Turning push off immediately
            // clears dismissal state and cancels any in-flight dismissal load.
            if featureFlags.isEnabled(.parentPortal) {
                await loadChildren(
                    includeDismissals: featureFlags.isEnabled(.pushNotifications)
                )
            } else {
                pendingDismissals = []
                isLoading = false
            }
        }
        .onDisappear {
            pendingDismissals = []
        }
    }

    private var dashboardFeatureState: Int {
        (featureFlags.isEnabled(.parentPortal) ? 2 : 0)
            + (featureFlags.isEnabled(.pushNotifications) ? 1 : 0)
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
            Button("Retry") {
                Task {
                    await loadChildren(
                        includeDismissals: featureFlags.isEnabled(.pushNotifications)
                    )
                }
            }
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
                    if featureFlags.isEnabled(.pushNotifications) {
                        ForEach(pendingDismissals) { dismissal in
                            safelyHomeCard(dismissal)
                        }
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
        guard featureFlags.isEnabled(.pushNotifications) else {
            pendingDismissals = []
            return
        }
        do {
            try await AttendanceService.shared.markSafelyHome(dismissalId: dismissal.id)
            pendingDismissals.removeAll { $0.id == dismissal.id }
        } catch {
            self.error = AppError("Couldn't confirm safely home. Please try again.", underlyingError: error)
        }
    }

    private func loadChildren(includeDismissals: Bool) async {
        isLoading = true
        loadFailed = false
        // Do not retain dismissals from an earlier enabled state while refreshing.
        pendingDismissals = []
        do {
            let loadedChildren = try await AttendanceService.shared.fetchParentChildren()
            guard !Task.isCancelled else { return }
            children = loadedChildren
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
        if includeDismissals {
            // Safely-home is best-effort decoration; a failure here must not hide
            // the children list. Re-check both cancellation and the live flag so a
            // stale request cannot repopulate state after the feature is disabled.
            let dismissals = (try? await AttendanceService.shared.fetchTodayDismissals()) ?? []
            guard !Task.isCancelled,
                  featureFlags.isEnabled(.parentPortal),
                  featureFlags.isEnabled(.pushNotifications) else {
                pendingDismissals = []
                return
            }
            pendingDismissals = ParentDismissalVisibility.visible(
                pushNotificationsEnabled: true,
                dismissals: dismissals
            )
        }
        isLoading = false
    }
}

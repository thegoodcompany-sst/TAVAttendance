import SwiftUI

/// Displays the current Data Protection Notice (PDPA s20 notification obligation).
/// Fetched from `policy_documents` where doc_type='data_protection_notice' AND is_current.
struct PrivacyNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var document: PolicyDocument?
    @State private var isLoading = true
    @State private var error: AppError?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(document.title)
                                .font(.title2.bold())
                            Text("Version \(document.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider()
                            Text(document.body)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "Notice Unavailable",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("We couldn't load the privacy notice. Please try again.")
                    )
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .errorAlertWithRetry(error: $error) { Task { await load() } }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            document = try await AttendanceService.shared.fetchPrivacyNotice()
        } catch {
            self.error = AppError(String(localized: "Failed to load privacy notice."), underlyingError: error)
        }
    }
}


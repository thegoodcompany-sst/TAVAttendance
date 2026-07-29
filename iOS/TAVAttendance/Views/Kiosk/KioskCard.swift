import SwiftUI

// MARK: - Student card

struct KioskCard: View {
    let entry: KioskEntry
    let isPending: Bool
    let isAdminMode: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let showPhoto: Bool
    let onAction: (GlobalKioskView.KioskAction) -> Void
    let onToggleSelection: () -> Void

    @State private var showLateReason = false
    @State private var showLateReasonAlert = false
    @State private var showMarkPresentConfirm = false
    @State private var showAbsentSignInConfirm = false   // UX-04
    @State private var photoURL: URL? = nil               // PROD-04

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private var statusColor: Color {
        if entry.isDismissed { return .purple }
        switch entry.status {
        case .present: return .green
        case .late:    return .orange
        case .absent:  return .red
        case .excused, nil: return Color(.tertiaryLabel)
        }
    }

    private var statusIcon: String {
        if entry.isDismissed { return "arrow.up.right.circle.fill" }
        switch entry.status {
        case .present: return "checkmark.circle.fill"
        case .late:    return "clock.badge.exclamationmark.fill"
        case .absent:  return "person.slash.fill"
        case .excused: return "person.badge.minus"
        case nil:      return "person.circle"
        }
    }

    private var statusLabel: String {
        if entry.isDismissed {
            if let t = entry.dismissedAt {
                return "Dismissed \(Self.timeFormatter.string(from: t))"
            }
            return "Dismissed"
        }
        switch entry.status {
        case .present: return "On Time"
        case .late:    return "Late"
        case .absent:  return "Absent"
        case .excused: return "Not Here"
        // A11Y-02: give the unsigned state a text label too, so it doesn't rely on
        // a grey icon alone to be distinguished from "Not Here".
        case nil:      return "Not Signed In"
        }
    }

    private var underlyingStatusLabel: String? {
        guard entry.isDismissed else { return nil }
        switch entry.status {
        case .present: return "On Time"
        case .late:    return "Late"
        default:       return nil
        }
    }

    private var canTap: Bool {
        if isSelectionMode { return true }
        guard !entry.isDismissed else { return false }
        // UX-04: absent cards are tappable for students too, to raise an "Are you
        // here?" confirmation (an escape hatch from an accidental absent mark).
        return entry.status == nil || entry.status == .excused || entry.status == .absent ||
            (isAdminMode && entry.status == .late)
    }

    var body: some View {
        Button {
            if isSelectionMode {
                onToggleSelection()
                return
            }
            if entry.status == nil || entry.status == .excused {
                onAction(.signIn)
            } else if entry.status == .absent && !isAdminMode {
                showAbsentSignInConfirm = true   // UX-04
            } else if isAdminMode && entry.status != .present {
                showMarkPresentConfirm = true
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                                .padding(10)
                        }
                    }

                if isPending {
                    ProgressView().controlSize(.large)
                } else {
                    VStack(spacing: 8) {
                        if showPhoto, entry.avatarUrl != nil {
                            avatarView   // PROD-04
                        } else {
                            Image(systemName: statusIcon)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(statusColor)
                                .accessibilityLabel(statusLabel)
                        }

                        Text(entry.fullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        // A11Y-02: always show a text status label (including the
                        // unsigned state) so colour/icon isn't the only signal.
                        VStack(spacing: 2) {
                                Text(statusLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor)
                                if let secondary = underlyingStatusLabel {
                                    Text(secondary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !entry.isDismissed, let status = entry.status {
                                    if status != .excused, let t = entry.markedAt {
                                        Text(Self.timeFormatter.string(from: t))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                    }
                                    if isAdminMode && status != .present && status != .excused {
                                        Text("Tap to change…")
                                            .font(.caption2.italic())
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 1)
                                    }
                                }
                                if isAdminMode, let reason = entry.lateReason, !entry.isDismissed {
                                    Button {
                                        showLateReasonAlert = true
                                    } label: {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 1)
                                    .alert("Late Reason", isPresented: $showLateReasonAlert) {
                                        Button("OK", role: .cancel) {}
                                    } message: {
                                        Text(reason)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 16)
                }
            }
            .frame(minHeight: 140)
            .scaleEffect(isPending ? 0.96 : 1.0)
            .animation(.spring(response: 0.25), value: isPending)
        }
        .buttonStyle(.plain)
        .disabled(isPending || !canTap)
        .animation(.spring(response: 0.3), value: entry.status)
        .animation(.spring(response: 0.3), value: entry.isDismissed)
        .animation(.spring(response: 0.2), value: isSelected)
        .contextMenu {
            if isAdminMode && !isSelectionMode { contextMenuContent }
        }
        .confirmationDialog(
            "Mark \(entry.fullName) as On Time?",
            isPresented: $showMarkPresentConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark as On Time") { onAction(.markPresent) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will override their current status.")
        }
        .sheet(isPresented: $showLateReason) {
            LateReasonSheet { reason in
                onAction(.addLateReason(reason))
                showLateReason = false
            } onCancel: {
                showLateReason = false
            }
        }
        .alert("Marked Absent", isPresented: $showAbsentSignInConfirm) {
            // UX-04 escape hatch — but "Absent" is a hard admin mark that a student
            // must NOT be able to undo themselves (see CLAUDE.md). So this is purely
            // informational: it explains the state and routes the student to a teacher,
            // who can override via admin mode. No attendance change happens here.
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(entry.fullName) is marked Absent. Please ask a teacher to sign you in.")
        }
    }

    // PROD-04: student photo with a small status badge, loaded via a signed URL.
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = photoURL {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.systemGray5)
                    }
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(3)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
        }
        .accessibilityLabel(statusLabel)
        .task {
            if photoURL == nil, let path = entry.avatarUrl {
                photoURL = try? await AttendanceService.shared.signedStudentPhotoURL(path: path)
            }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if !entry.isDismissed {
            if entry.status != .late && entry.status != .absent {
                Button {
                    onAction(.markLate)
                } label: {
                    Label("Mark as Late", systemImage: "clock.badge.exclamationmark")
                }
            }
            if entry.status == .late || entry.status == .present {
                Button {
                    onAction(.markNotHere)
                } label: {
                    Label("Mark as Not Here", systemImage: "person.badge.minus")
                }
            }
            if isAdminMode {
                if (entry.status == .present || entry.status == .late) && !entry.isDismissed {
                    Button {
                        onAction(.markDismissed)
                    } label: {
                        Label("Mark as Dismissed", systemImage: "figure.walk.departure")
                    }
                }
                if entry.status == .late {
                    Button {
                        showLateReason = true
                    } label: {
                        Label(entry.lateReason == nil ? "Add Late Reason…" : "Edit Late Reason…", systemImage: "pencil")
                    }
                }
                if entry.status != .present && entry.status != nil && entry.status != .excused {
                    Button {
                        onAction(.markPresent)
                    } label: {
                        Label("Mark as On Time", systemImage: "checkmark.circle")
                    }
                }
                if entry.status != .absent {
                    Button(role: .destructive) {
                        onAction(.markAbsent)
                    } label: {
                        Label("Mark as Absent", systemImage: "person.slash")
                    }
                }
            }
        } else if isAdminMode {
            Button {
                onAction(.undoDismissal)
            } label: {
                Label("Undo Dismissal", systemImage: "arrow.uturn.left")
            }
        }
    }
}

// MARK: - Late reason sheet

struct LateReasonSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    private let presets = ["Traffic", "Bus delay", "Overslept", "Sick", "Family", "Other"]
    @State private var selected: String? = nil
    @State private var freeText = ""

    private var isOther: Bool { selected == "Other" }
    private var effectiveText: String { isOther ? freeText : (selected ?? freeText) }
    private var canSave: Bool { !effectiveText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Select a reason or enter your own.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            selected = preset
                            if preset != "Other" { freeText = "" }
                        } label: {
                            Text(preset)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(selected == preset ? Color.accentColor : Color(.systemGray5), in: Capsule())
                                .foregroundStyle(selected == preset ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if isOther || selected == nil {
                    TextField("Enter reason…", text: $freeText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Late Reason")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(effectiveText.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

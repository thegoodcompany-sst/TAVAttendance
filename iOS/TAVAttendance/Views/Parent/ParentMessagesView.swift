import SwiftUI

/// Per-child private message thread (parent portal Phase 2). Parent bubbles on the
/// trailing edge; TAVA replies on the leading edge.
struct ParentMessagesView: View {
    let studentId: UUID

    @State private var messages: [ParentMessage] = []
    @State private var isLoading = true
    @State private var loadError: AppError?
    @State private var subjectText = ""
    @State private var bodyText = ""
    @State private var isSending = false
    @State private var sendError: AppError?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading {
                    ProgressView("Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    VStack(spacing: 12) {
                        Text(err.message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Send a message to TAVA about this child.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(messages) { msg in
                                    messageBubble(msg)
                                        .id(msg.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
            }

            Divider()
            composer
        }
        .task { await load() }
        .errorAlert(error: $sendError)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextField("Subject (optional)", text: $subjectText)
                .textFieldStyle(.roundedBorder)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $bodyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private func messageBubble(_ msg: ParentMessage) -> some View {
        let fromParent = msg.isFromParent
        return HStack {
            if fromParent { Spacer(minLength: 48) }
            VStack(alignment: fromParent ? .trailing : .leading, spacing: 4) {
                if let subject = msg.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fromParent ? Color.white.opacity(0.9) : .secondary)
                }
                Text(msg.body)
                    .font(.subheadline)
                    .foregroundStyle(fromParent ? .white : .primary)
                if let sent = msg.sentAt {
                    Text(timeFormatter.string(from: sent))
                        .font(.caption2)
                        .foregroundStyle(fromParent ? Color.white.opacity(0.7) : .secondary)
                }
            }
            .padding(10)
            .background(
                fromParent ? Color.accentColor : Color(.secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 14)
            )
            if !fromParent { Spacer(minLength: 48) }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            messages = try await AttendanceService.shared.fetchMessages(studentId: studentId)
        } catch {
            loadError = AppError(
                String(localized: "Couldn't load messages. Check your connection and try again."),
                underlyingError: error
            )
        }
        isLoading = false
    }

    private func send() async {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        isSending = true
        sendError = nil
        let trimmedSubject = subjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await AttendanceService.shared.sendParentMessage(
                studentId: studentId,
                subject: trimmedSubject.isEmpty ? nil : trimmedSubject,
                body: trimmedBody
            )
            bodyText = ""
            subjectText = ""
            await load()
        } catch {
            sendError = AppError(
                String(localized: "Couldn't send message. Please try again."),
                underlyingError: error
            )
        }
        isSending = false
    }
}

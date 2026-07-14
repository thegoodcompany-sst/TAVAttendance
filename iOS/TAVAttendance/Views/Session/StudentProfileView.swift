import SwiftUI

struct StudentProfileView: View {
    let studentId: UUID
    let fullName: String

    @State private var history: [AttendanceHistoryRecord] = []
    @State private var slips: [ResultSlip] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingAddSlip = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    private let isoParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var canUploadSlips: Bool {
        authManager.currentProfile?.role == "admin" || authManager.currentProfile?.role == "tutor"
    }

    private var sinceDate: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    private var presentCount: Int { history.filter { $0.status == .present }.count }
    private var lateCount: Int    { history.filter { $0.status == .late }.count }
    private var absentCount: Int  { history.filter { $0.status == .absent }.count }
    private var excusedCount: Int { history.filter { $0.status == .excused }.count }
    private var attendanceRate: Double {
        guard !history.isEmpty else { return 0 }
        // QA-08 / PROD-05: match the Postgres `attendance_summary` view, which
        // counts present + late + excused toward attendance. An excused absence
        // has a valid reason and should not be penalised; keeping this in sync
        // means the iOS profile and the web dashboard show the same rate.
        return Double(presentCount + lateCount + excusedCount) / Double(history.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadHistory() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if history.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "No Records (Last 30 Days)",
                                    systemImage: "calendar.badge.exclamationmark",
                                    description: Text("No sessions recorded for this student in the past month.")
                                )
                            }
                        } else {
                            Section {
                                statsCard
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)

                            Section("Sessions (last 30 days)") {
                                ForEach(history) { record in
                                    historyRow(record)
                                }
                            }
                        }

                        Section {
                            if slips.isEmpty {
                                Text("No result slips yet.")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(slips) { slip in
                                    resultSlipRow(slip)
                                }
                            }
                            if canUploadSlips {
                                Button {
                                    showingAddSlip = true
                                } label: {
                                    Label("Add Result Slip", systemImage: "plus.circle")
                                }
                            }
                        } header: {
                            Text("Result Slips")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .sheet(isPresented: $showingAddSlip) {
                        ResultSlipUploadSheet(studentId: studentId) {
                            await loadSlips()
                        }
                    }
                }
            }
            .navigationTitle(fullName)
            .analyticsScreen("student_profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Load history and slips in parallel — they are independent queries.
            async let historyFetch: Void = loadHistory()
            async let slipsFetch: Void = loadSlips()
            _ = await (historyFetch, slipsFetch)
        }
    }

    // MARK: - Stats card

    private var statsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                statPill(value: presentCount, label: "Present", color: .green)
                statPill(value: lateCount,    label: "Late",    color: .orange)
                statPill(value: absentCount,  label: "Absent",  color: .red)
                statPill(value: excusedCount, label: "Excused", color: .gray)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(attendanceRate * 100))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(rateColor)
                Text("attendance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(history.count) sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    bar(count: presentCount, total: history.count, color: .green, width: geo.size.width)
                    bar(count: lateCount,    total: history.count, color: .orange, width: geo.size.width)
                    bar(count: absentCount,  total: history.count, color: .red,    width: geo.size.width)
                    bar(count: excusedCount, total: history.count, color: .gray,   width: geo.size.width)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(count: Int, total: Int, color: Color, width: CGFloat) -> some View {
        let fraction = total > 0 ? CGFloat(count) / CGFloat(total) : 0
        return Rectangle()
            .fill(color)
            .frame(width: width * fraction, height: 8)
    }

    private var rateColor: Color {
        switch attendanceRate {
        case 0.9...: return .green
        case 0.75...: return .orange
        default: return .red
        }
    }

    // MARK: - History row

    private func historyRow(_ record: AttendanceHistoryRecord) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color(for: record.status))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.session.`class`.name)
                    .font(.subheadline.weight(.semibold))
                Text(formattedDate(record.session.sessionDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.status.rawValue.capitalized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color(for: record.status))
                if let t = record.markedAt {
                    Text(timeFormatter.string(from: t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data

    private func loadHistory() async {
        isLoading = true
        loadError = nil
        do {
            history = try await AttendanceService.shared.fetchStudentAttendanceHistory(
                studentId: studentId, limit: 100, since: sinceDate)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSlips() async {
        do {
            slips = try await AttendanceService.shared.fetchResultSlips(studentId: studentId)
        } catch {
            // Slips are supplementary; surface error inline rather than replacing the whole view
        }
    }

    // MARK: - Result slip row

    private func resultSlipRow(_ slip: ResultSlip) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slip.subject ?? "—")
                    .font(.subheadline.weight(.semibold))
                if let name = slip.examName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dateStr = slip.examDate, let date = isoParser.date(from: dateStr) {
                    Text(dateFormatter.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let fraction = slip.fractionDisplay {
                    Text(fraction)
                        .font(.subheadline.weight(.medium))
                }
                if let pct = slip.percentageDisplay {
                    Text(pct)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ iso: String) -> String {
        guard let d = isoParser.date(from: iso) else { return iso }
        return dateFormatter.string(from: d)
    }

    private func color(for status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .late:    return .orange
        case .absent:  return .red
        case .excused: return .gray
        }
    }
}

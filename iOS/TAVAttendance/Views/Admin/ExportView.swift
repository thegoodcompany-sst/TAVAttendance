import SwiftUI
import UniformTypeIdentifiers

private enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case pdf = "PDF"
}

// A local struct to decode attendance + session date together.
// PostgREST joins the session row via the FK; we decode only what we need.
private struct ExportRecord: Codable {
    let id: UUID?
    let sessionId: UUID
    let studentId: UUID
    let status: AttendanceStatus
    let markedAt: Date?
    let lateReason: String?
    let session: ExportSession?

    struct ExportSession: Codable {
        let sessionDate: String
        enum CodingKeys: String, CodingKey { case sessionDate = "session_date" }
    }

    enum CodingKeys: String, CodingKey {
        case id, status, session
        case sessionId  = "session_id"
        case studentId  = "student_id"
        case markedAt   = "marked_at"
        case lateReason = "late_reason"
    }
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var classes: [TAVClass] = []
    @State private var students: [Student] = []
    @State private var selectedClassId: UUID? = nil
    @State private var fromDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var format: ExportFormat = .csv
    @State private var isExporting = false
    @State private var exportURL: URL? = nil
    @State private var showShare = false
    @State private var errorMessage: String? = nil
    @State private var error: AppError? = nil

    private let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    if classes.isEmpty {
                        ProgressView()
                    } else {
                        Picker("Class", selection: $selectedClassId) {
                            Text("Select a class…").tag(Optional<UUID>(nil))
                            ForEach(classes) { cls in
                                Text(cls.name).tag(Optional(cls.id))
                            }
                        }
                    }
                }

                Section("Date Range") {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, in: fromDate..., displayedComponents: .date)
                }

                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task { await export() }
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                            } else {
                                Text("Export")
                            }
                            Spacer()
                        }
                    }
                    .disabled(selectedClassId == nil || isExporting)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Export Attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                do {
                    async let cls = AttendanceService.shared.fetchMyClasses()
                    async let sts = AttendanceService.shared.fetchAllStudents()
                    (classes, students) = try await (cls, sts)
                } catch {
                    self.error = AppError("Failed to load data", underlyingError: error)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareLink(item: url)
            }
        }
        .errorAlert(error: $error)
    }

    // MARK: - Export logic

    private func export() async {
        guard let classId = selectedClassId else { return }
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let records = try await AttendanceService.shared.fetchAttendanceForExport(
                classId: classId, from: fromDate, to: toDate)

            let studentMap: [UUID: String] = Dictionary(
                uniqueKeysWithValues: students.map { ($0.id, $0.fullName) })
            let className = classes.first(where: { $0.id == classId })?.name ?? "Unknown"

            let url: URL
            switch format {
            case .csv:
                url = try buildCSV(records: records, studentMap: studentMap, className: className)
            case .pdf:
                url = try buildPDF(records: records, studentMap: studentMap, className: className)
            }
            exportURL = url
            showShare = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildCSV(
        records: [AttendanceRecord],
        studentMap: [UUID: String],
        className: String
    ) throws -> URL {
        var lines = ["Date,Class,Student,Status,Late Reason,Marked At,Dismissed At"]
        for r in records {
            // markedAt used as proxy for session date (dedicated export query joins sessions but
            // AttendanceRecord model doesn't carry sessionDate — using markedAt date portion)
            let dateStr: String
            if let ma = r.markedAt {
                dateStr = isoFmt.string(from: ma)
            } else {
                dateStr = ""
            }
            let studentName = studentMap[r.studentId] ?? r.studentId.uuidString
            let markedAtStr: String
            if let ma = r.markedAt {
                let tf = DateFormatter(); tf.dateStyle = .short; tf.timeStyle = .short
                markedAtStr = tf.string(from: ma)
            } else {
                markedAtStr = ""
            }
            let row = [
                dateStr,
                escapedCSV(className),
                escapedCSV(studentName),
                r.status.rawValue,
                escapedCSV(r.lateReason ?? ""),
                markedAtStr,
                "" // Dismissed At — deferred
            ].joined(separator: ",")
            lines.append(row)
        }
        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attendance_\(isoFmt.string(from: fromDate))_\(isoFmt.string(from: toDate)).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func escapedCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func buildPDF(
        records: [AttendanceRecord],
        studentMap: [UUID: String],
        className: String
    ) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attendance_\(isoFmt.string(from: fromDate))_\(isoFmt.string(from: toDate)).pdf")

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let titleFont = UIFont.boldSystemFont(ofSize: 16)
            let headerFont = UIFont.boldSystemFont(ofSize: 10)
            let bodyFont = UIFont.systemFont(ofSize: 10)

            // Title
            let title = "Attendance Export — \(className)"
            title.draw(at: CGPoint(x: 36, y: 36), withAttributes: [.font: titleFont])

            let range = "\(isoFmt.string(from: fromDate)) to \(isoFmt.string(from: toDate))"
            range.draw(at: CGPoint(x: 36, y: 58), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel])

            // Column headers
            let colX: [CGFloat] = [36, 150, 320, 430]
            let headers = ["Date", "Student", "Class", "Status"]
            let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont]
            var y: CGFloat = 90
            for (i, h) in headers.enumerated() {
                h.draw(at: CGPoint(x: colX[i], y: y), withAttributes: headerAttrs)
            }
            y += 16
            UIColor.separator.setFill()
            UIBezierPath(rect: CGRect(x: 36, y: y, width: 540, height: 0.5)).fill()
            y += 6

            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
            for r in records {
                if y > pageRect.height - 60 {
                    ctx.beginPage()
                    y = 36
                }
                let dateStr: String
                if let ma = r.markedAt { dateStr = isoFmt.string(from: ma) } else { dateStr = "—" }
                let student = studentMap[r.studentId] ?? r.studentId.uuidString
                let cols = [dateStr, student, className, r.status.rawValue]
                for (i, col) in cols.enumerated() {
                    col.draw(at: CGPoint(x: colX[i], y: y), withAttributes: bodyAttrs)
                }
                y += 16
            }
        }
        try data.write(to: url)
        return url
    }
}

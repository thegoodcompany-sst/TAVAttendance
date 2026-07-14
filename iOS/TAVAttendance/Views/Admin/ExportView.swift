import SwiftUI
import UniformTypeIdentifiers

private enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case pdf = "PDF"
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var classes: [TAVClass] = []
    @State private var selectedClassId: UUID? = nil
    @State private var fromDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var format: ExportFormat = .csv
    @State private var isExporting = false
    @State private var exportURL: URL? = nil
    @State private var showShare = false
    // MAINT-07: a single error channel surfaced via `.errorAlert`.
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

            }
            .navigationTitle("Export Attendance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // PERF-07: only the class list is needed to render the form;
                // students are fetched lazily inside export().
                do {
                    classes = try await AttendanceService.shared.fetchMyClasses()
                } catch {
                    self.error = AppError("Failed to load classes", underlyingError: error)
                }
            }
        }
        .sheet(isPresented: $showShare, onDismiss: cleanupExportFile) {
            if let url = exportURL {
                ShareLink(item: url)
            }
        }
        .errorAlert(error: $error)
        .analyticsScreen("export")
    }

    // MARK: - Export logic

    private func export() async {
        guard let classId = selectedClassId else { return }
        isExporting = true
        defer { isExporting = false }
        Analytics.shared.track(.tap, name: "export_\(format.rawValue.lowercased())",
                               properties: ["screen": .string("export")])
        let started = Date()

        do {
            // PERF-07: fetch students only now, when an export is actually requested.
            async let recordsFetch = AttendanceService.shared.fetchAttendanceForExport(
                classId: classId, from: fromDate, to: toDate)
            async let studentsFetch = AttendanceService.shared.fetchAllStudents()
            let (records, students) = try await (recordsFetch, studentsFetch)

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
            Analytics.shared.track(.latency, name: "export_generate", properties: [
                "record_count": .integer(records.count),
                "duration_ms": Analytics.ms(since: started),
            ])
        } catch {
            self.error = AppError("Export failed", underlyingError: error)
        }
    }

    private func buildCSV(
        records: [AttendanceExportRecord],
        studentMap: [UUID: String],
        className: String
    ) throws -> URL {
        var lines = ["Date,Class,Student,Status,Late Reason,Marked At,Dismissed At"]
        for r in records {
            // QA-04: use the true session date from the joined session, not markedAt.
            let dateStr = r.sessionDate
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
        // PDPA: encrypt at rest while the export awaits the share sheet.
        try Data(csv.utf8).write(to: url, options: [.completeFileProtection])
        return url
    }

    // PDPA: attendance exports are personal data — remove the temp file once the
    // share sheet closes rather than leaving it in the temp dir.
    private func cleanupExportFile() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
        }
        exportURL = nil
    }

    private func escapedCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func buildPDF(
        records: [AttendanceExportRecord],
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
                let dateStr = r.sessionDate.isEmpty ? "—" : r.sessionDate
                let student = studentMap[r.studentId] ?? r.studentId.uuidString
                let cols = [dateStr, student, className, r.status.rawValue]
                for (i, col) in cols.enumerated() {
                    col.draw(at: CGPoint(x: colX[i], y: y), withAttributes: bodyAttrs)
                }
                y += 16
            }
        }
        try data.write(to: url, options: [.completeFileProtection])
        return url
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct StudentImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var parsedRows: [StudentInsert] = []
    @State private var importErrors: [String] = []
    @State private var isImporting = false
    @State private var importResult: String? = nil

    // PDPA consent attestation
    @State private var consentObtained = false
    @State private var noticeVersion: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Select CSV File") { showFilePicker = true }
                } footer: {
                    Text("CSV columns (first row is header, ignored): full_name, school, year_of_study")
                }

                if !parsedRows.isEmpty {
                    Section("Preview (\(parsedRows.count) students)") {
                        ForEach(parsedRows.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(parsedRows[i].fullName).bold()
                                if let s = parsedRows[i].school {
                                    Text(s).font(.caption).foregroundStyle(.secondary)
                                }
                                if let y = parsedRows[i].yearOfStudy {
                                    Text(y).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Section {
                        Toggle(isOn: $consentObtained) {
                            Text("Parent/guardian consent obtained for all \(parsedRows.count) children")
                        }
                    } footer: {
                        Text("Required (PDPA). Confirm consent was obtained offline for every student in this file. A consent record is logged for each on import.")
                    }

                    Section {
                        Button {
                            Task { await doImport() }
                        } label: {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                } else {
                                    Text("Import \(parsedRows.count) Students")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isImporting || !consentObtained)
                    }
                }

                if let result = importResult {
                    Section {
                        Text(result).foregroundStyle(.green)
                    }
                }

                if !importErrors.isEmpty {
                    Section("Warnings") {
                        ForEach(importErrors, id: \.self) { e in
                            Text(e).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Import Students")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText]
            ) { result in
                if case .success(let url) = result {
                    parseCSV(url: url)
                }
            }
            .task {
                noticeVersion = try? await AttendanceService.shared.fetchPrivacyNotice()?.version
            }
        }
    }

    // MARK: - CSV parsing

    private func parseCSV(url: URL) {
        let gained = url.startAccessingSecurityScopedResource()
        defer { if gained { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            importErrors = ["Could not read file. Make sure it is a plain-text CSV."]
            return
        }

        let lines = raw.components(separatedBy: .newlines)
        var rows: [StudentInsert] = []
        var warnings: [String] = []

        for (idx, line) in lines.enumerated() {
            // Skip header row and blank lines
            if idx == 0 || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let cols = parseCSVLine(line)
            let name = cols.indices.contains(0) ? cols[0].trimmingCharacters(in: .whitespaces) : ""
            if name.isEmpty {
                warnings.append("Row \(idx + 1): empty name, skipped.")
                continue
            }
            let school = cols.indices.contains(1) ? nilIfEmpty(cols[1]) : nil
            let year   = cols.indices.contains(2) ? nilIfEmpty(cols[2]) : nil
            rows.append(StudentInsert(fullName: name, school: school, yearOfStudy: year))
        }

        parsedRows = rows
        importErrors = warnings
        importResult = nil
    }

    /// Minimal RFC-4180–aware CSV line splitter (handles quoted fields with embedded commas
    /// and escaped double-quotes: "" inside a quoted field represents a literal ").
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var scalars = Array(line.unicodeScalars)
        var i = scalars.startIndex

        while i < scalars.endIndex {
            let ch = scalars[i]
            switch ch {
            case "\"":
                if inQuotes {
                    // Peek at the next character — if it is also a quote this is an
                    // RFC-4180 escaped quote ("" → literal "); otherwise it closes the field.
                    let next = scalars.index(after: i)
                    if next < scalars.endIndex && scalars[next] == "\"" {
                        current.unicodeScalars.append("\"")
                        i = scalars.index(after: next)  // skip both quotes
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            case ",":
                if inQuotes {
                    current.append(",")
                } else {
                    fields.append(current)
                    current = ""
                }
            default:
                current.unicodeScalars.append(ch)
            }
            i = scalars.index(after: i)
        }
        fields.append(current)
        return fields
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Import action

    private func doImport() async {
        // PDPA: hard guard — never import without attested consent.
        guard consentObtained else {
            importErrors.append("Confirm parental/guardian consent before importing.")
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let created = try await AttendanceService.shared.bulkCreateStudents(parsedRows)
            // Log a consent record for each newly-created student.
            try await AttendanceService.shared.recordConsentBulk(
                studentIds: created.map(\.id), noticeVersion: noticeVersion)
            importResult = "Successfully imported \(created.count) student(s) and logged consent."
            parsedRows = []
            consentObtained = false
        } catch {
            importErrors.append("Import failed: \(error.localizedDescription)")
        }
    }
}

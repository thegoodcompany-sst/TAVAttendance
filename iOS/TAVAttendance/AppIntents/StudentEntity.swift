import Foundation
import AppIntents

/// An App Intents entity representing a student, so Siri and the Shortcuts app can
/// resolve a spoken name (e.g. "Wayne Tan") to a concrete student record.
struct StudentEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Student"

    static var defaultQuery = StudentEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ student: Student) {
        self.id = student.id
        self.name = student.fullName
    }
}

/// Resolves `StudentEntity` values for App Intents. Supports lookup by id (when an
/// intent is re-run with a saved parameter) and free-text name matching so Siri can
/// disambiguate by what the user said.
struct StudentEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [StudentEntity] {
        let students = try await AttendanceService.shared.fetchAllStudents()
        let wanted = Set(identifiers)
        return students.filter { wanted.contains($0.id) }.map(StudentEntity.init)
    }

    func entities(matching string: String) async throws -> [StudentEntity] {
        let students = try await AttendanceService.shared.fetchAllStudents()
        let needle = string.lowercased()
        return students
            .filter { $0.fullName.lowercased().contains(needle) }
            .map(StudentEntity.init)
    }

    func suggestedEntities() async throws -> [StudentEntity] {
        try await AttendanceService.shared.fetchAllStudents().map(StudentEntity.init)
    }
}

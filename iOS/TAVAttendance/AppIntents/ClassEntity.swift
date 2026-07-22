import Foundation
import AppIntents

/// An App Intents entity representing a class, so Siri and the Shortcuts app can
/// resolve a spoken class name (e.g. "P5 Math") to a concrete class record.
struct ClassEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Class"

    static var defaultQuery = ClassEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ cls: TAVClass) {
        self.id = cls.id
        self.name = cls.name
    }
}

/// Resolves `ClassEntity` values for App Intents over the active classes.
struct ClassEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [ClassEntity] {
        try await IntentSupport.requireSensitiveEntityQueryAuthorization()
        let classes = try await AttendanceService.shared.fetchMyClasses()
        let wanted = Set(identifiers)
        return classes.filter { wanted.contains($0.id) }.map(ClassEntity.init)
    }

    func entities(matching string: String) async throws -> [ClassEntity] {
        try await IntentSupport.requireSensitiveEntityQueryAuthorization()
        let classes = try await AttendanceService.shared.fetchMyClasses()
        let needle = string.lowercased()
        return classes
            .filter { $0.name.lowercased().contains(needle) }
            .map(ClassEntity.init)
    }

    func suggestedEntities() async throws -> [ClassEntity] {
        try await IntentSupport.requireSensitiveEntityQueryAuthorization()
        return try await AttendanceService.shared.fetchMyClasses().map(ClassEntity.init)
    }
}

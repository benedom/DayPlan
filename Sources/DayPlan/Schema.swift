import Foundation
import SwiftData

// MARK: - Versioned schema

/// The shipped shape of the store. Pinning it means every future model change
/// becomes an explicit V2 + migration stage instead of an implicit, untested
/// lightweight migration against whatever the current source happens to be.
///
/// To evolve the schema:
///  1. Copy the current model definitions into `DayPlanSchemaV2` (a new file),
///     leaving V1 untouched, since it describes stores already on disk.
///  2. Add the new version to `DayPlanMigrationPlan.schemas`.
///  3. Add a `MigrationStage` from V1 to V2 (`.lightweight` when adding
///     optional / defaulted properties, `.custom` when data must be rewritten).
enum DayPlanSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TodoList.self, Todo.self]
    }

    /// Frozen exactly as it shipped. Never edit these two types again: change
    /// `Todo`/`TodoList` in `Models.swift` (the current shape) instead, and add
    /// a new versioned schema for the difference.
    @Model
    final class TodoList {
        var name: String = "New List"
        var colorName: String = "blue"
        var sortIndex: Int = 0
        var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Todo.list)
        var todos: [Todo] = []

        init(name: String, colorName: String = "blue", sortIndex: Int = 0) {
            self.name = name
            self.colorName = colorName
            self.sortIndex = sortIndex
            self.createdAt = Date()
        }
    }

    @Model
    final class Todo {
        var title: String = ""
        var notes: String = ""
        var priorityRaw: Int = 0
        var dueDate: Date?
        var isDone: Bool = false
        var completedAt: Date?
        var createdAt: Date = Date()
        var pinnedDay: Date?
        var excludedDay: Date?
        var list: TodoList?

        init(title: String,
             notes: String = "",
             priorityRaw: Int = 0,
             dueDate: Date? = nil,
             list: TodoList? = nil) {
            self.title = title
            self.notes = notes
            self.priorityRaw = priorityRaw
            self.dueDate = dueDate
            self.list = list
            self.isDone = false
            self.createdAt = Date()
        }
    }
}

/// Adds time tracking: a new `TimeEntry` model, plus the `Todo.timeEntries`
/// relationship. Both live on the current `Todo`/`TodoList` in `Models.swift`,
/// since V2 is the current shape.
enum DayPlanSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TodoList.self, Todo.self, TimeEntry.self]
    }
}

enum DayPlanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [DayPlanSchemaV1.self, DayPlanSchemaV2.self]
    }

    /// Adding a new model and a new relationship to it needs no data rewrite.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: DayPlanSchemaV1.self, toVersion: DayPlanSchemaV2.self)]
    }
}

extension Schema {
    /// The schema the app opens stores with: always the newest known version.
    static var dayPlanCurrent: Schema {
        Schema(versionedSchema: DayPlanSchemaV2.self)
    }
}

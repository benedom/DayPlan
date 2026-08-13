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
}

enum DayPlanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [DayPlanSchemaV1.self]
    }

    /// Empty until a V2 exists. One stage per version hop, in order.
    static var stages: [MigrationStage] { [] }
}

extension Schema {
    /// The schema the app opens stores with: always the newest known version.
    static var dayPlanCurrent: Schema {
        Schema(versionedSchema: DayPlanSchemaV1.self)
    }
}

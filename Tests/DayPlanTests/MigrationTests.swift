import Foundation
import SwiftData
import Testing
@testable import DayPlan

/// Guards the one scenario that cannot be checked against a freshly created
/// container: a store already on a user's disk, written by an older build,
/// being opened by this one. Every future schema version should add a case
/// here, since a broken stage means real data loss rather than a failed test.
@MainActor
@Suite("Schema migration")
struct MigrationTests {
    @Test("A V1 store opens as V2 with its todos intact")
    func migratesV1StoreToV2() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DayPlanMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("DayPlan.store")

        // Write through the frozen V1 schema with no migration plan, so the file
        // is stamped V1 exactly as the shipped build left it.
        do {
            let schema = Schema(versionedSchema: DayPlanSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
            let context = ModelContext(container)
            let list = DayPlanSchemaV1.TodoList(name: "Work")
            context.insert(list)
            let todo = DayPlanSchemaV1.Todo(title: "Predates time tracking", list: list)
            todo.notes = "kept"
            context.insert(todo)
            try context.save()
        }

        // Reopen through the real plan the app ships with.
        let container = try ModelContainer(
            for: .dayPlanCurrent,
            migrationPlan: DayPlanMigrationPlan.self,
            configurations: ModelConfiguration(schema: .dayPlanCurrent, url: url)
        )
        let context = ModelContext(container)

        let todos = try context.fetch(FetchDescriptor<Todo>())
        #expect(todos.count == 1)
        let migrated = try #require(todos.first)
        #expect(migrated.title == "Predates time tracking")
        #expect(migrated.notes == "kept")
        #expect(migrated.list?.name == "Work")

        // The new relationship must come back empty, not absent or faulted.
        #expect(migrated.timeEntries.isEmpty)
        #expect(migrated.totalTrackedMinutes == 0)
        #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 0)

        // And the migrated store must accept the new model.
        context.insert(TimeEntry(minutes: 90, day: Date(), todo: migrated))
        try context.save()
        #expect(migrated.totalTrackedMinutes == 90)
    }
}

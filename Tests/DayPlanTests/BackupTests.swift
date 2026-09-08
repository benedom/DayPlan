import Foundation
import SwiftData
import Testing
@testable import DayPlan

@MainActor
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(schema: .dayPlanCurrent, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: .dayPlanCurrent,
                                       migrationPlan: DayPlanMigrationPlan.self,
                                       configurations: config)
    return ModelContext(container)
}

private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_756_000_000))

/// A store with one list, two todos, and three time entries across two days.
@MainActor
private func seed(_ context: ModelContext) throws -> Data {
    let work = TodoList(name: "Work")
    context.insert(work)
    let first = Todo(title: "Ship the parser fix", list: work)
    let second = Todo(title: "Unfiled errand")
    context.insert(first)
    context.insert(second)
    context.insert(TimeEntry(minutes: 90, day: day, todo: first))
    context.insert(TimeEntry(minutes: 30, day: day, todo: first))
    context.insert(TimeEntry(minutes: 45, day: day.addingTimeInterval(-86_400), todo: second))
    try context.save()
    return try BackupService.exportData(from: context)
}

@MainActor
@Suite("Backup round trip")
struct BackupTests {
    @Test("Export then restore preserves time entries and their todo")
    func roundTripPreservesTimeEntries() throws {
        let source = try makeContext()
        let data = try seed(source)

        let target = try makeContext()
        let summary = try BackupService.restore(from: data, into: target, mode: .replace)

        #expect(summary.todosCreated == 2)
        #expect(summary.timeEntriesCreated == 3)

        let todos = try target.fetch(FetchDescriptor<Todo>())
        let restored = try #require(todos.first { $0.title == "Ship the parser fix" })
        #expect(restored.trackedMinutes(on: day) == 120)
        #expect(restored.totalTrackedMinutes == 120)
        #expect(restored.list?.name == "Work")

        let errand = try #require(todos.first { $0.title == "Unfiled errand" })
        #expect(errand.totalTrackedMinutes == 45)
        #expect(errand.list == nil)
    }

    /// The whole point of the dedup bookkeeping in `restore`: a user who merges
    /// the same file twice must not end up with doubled time.
    @Test("Merging the same file twice is idempotent")
    func mergeIsIdempotent() throws {
        let source = try makeContext()
        let data = try seed(source)

        let target = try makeContext()
        let first = try BackupService.restore(from: data, into: target, mode: .merge)
        #expect(first.todosCreated == 2)
        #expect(first.timeEntriesCreated == 3)

        let second = try BackupService.restore(from: data, into: target, mode: .merge)
        #expect(second.todosCreated == 0)
        #expect(second.todosSkipped == 2)
        #expect(second.timeEntriesCreated == 0)

        #expect(try target.fetchCount(FetchDescriptor<Todo>()) == 2)
        #expect(try target.fetchCount(FetchDescriptor<TimeEntry>()) == 3)
        let restored = try #require(try target.fetch(FetchDescriptor<Todo>())
            .first { $0.title == "Ship the parser fix" })
        #expect(restored.totalTrackedMinutes == 120)
    }

    @Test("Merging into an existing store attaches entries without duplicating todos")
    func mergeOntoExistingTodos() throws {
        let source = try makeContext()
        let data = try seed(source)

        // A second export of the same data carries fresh file-local ids; the
        // dedup must key off the todo identity, not those ids.
        let other = try makeContext()
        _ = try BackupService.restore(from: data, into: other, mode: .replace)
        let reExported = try BackupService.exportData(from: other)

        let summary = try BackupService.restore(from: reExported, into: other, mode: .merge)
        #expect(summary.todosSkipped == 2)
        #expect(summary.timeEntriesCreated == 0)
        #expect(try other.fetchCount(FetchDescriptor<TimeEntry>()) == 3)
    }

    /// Backups written before time tracking have no `timeEntries` array and no
    /// `id` on each todo. Synthesized `Decodable` treats a missing key as
    /// `keyNotFound` rather than using the default, so `restore` must keep
    /// accepting these or every existing backup on disk becomes unreadable.
    @Test("Backups written before time tracking still restore")
    func restoresPreTimeTrackingBackups() throws {
        let legacy = """
        {
          "appVersion" : "1.0",
          "exportedAt" : "2026-09-01T10:00:00Z",
          "formatVersion" : 1,
          "lists" : [ { "colorName" : "blue", "createdAt" : "2026-08-01T09:00:00Z",
                        "id" : "11111111-1111-1111-1111-111111111111",
                        "name" : "Work", "sortIndex" : 0 } ],
          "schemaVersion" : "1.0.0",
          "todos" : [ { "createdAt" : "2026-08-02T09:00:00Z", "isDone" : false,
                        "listID" : "11111111-1111-1111-1111-111111111111",
                        "notes" : "kept", "priorityRaw" : 1, "title" : "Old todo" } ]
        }
        """

        let context = try makeContext()
        let summary = try BackupService.restore(from: Data(legacy.utf8), into: context, mode: .replace)

        #expect(summary.todosCreated == 1)
        #expect(summary.listsCreated == 1)
        #expect(summary.timeEntriesCreated == 0)

        let todo = try #require(try context.fetch(FetchDescriptor<Todo>()).first)
        #expect(todo.title == "Old todo")
        #expect(todo.notes == "kept")
        #expect(todo.list?.name == "Work")
        #expect(todo.totalTrackedMinutes == 0)
    }
}

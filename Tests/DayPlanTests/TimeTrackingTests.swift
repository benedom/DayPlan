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
private let otherDay = Calendar.current.date(byAdding: .day, value: -1, to: day)!

@MainActor
@Suite("Tracked time")
struct TrackedTimeTests {
    @Test("trackedMinutes sums one day and ignores the rest")
    func trackedMinutesIsPerDay() throws {
        let context = try makeContext()
        let todo = Todo(title: "Write the migration")
        context.insert(todo)
        context.insert(TimeEntry(minutes: 60, day: day, todo: todo))
        context.insert(TimeEntry(minutes: 30, day: day, todo: todo))
        context.insert(TimeEntry(minutes: 45, day: otherDay, todo: todo))

        #expect(todo.trackedMinutes(on: day) == 90)
        #expect(todo.trackedMinutes(on: otherDay) == 45)
        #expect(todo.totalTrackedMinutes == 135)
    }

    @Test("A day is matched by calendar day, not by instant")
    func matchesWholeDay() throws {
        let context = try makeContext()
        let todo = Todo(title: "Late entry")
        context.insert(todo)
        context.insert(TimeEntry(minutes: 60, day: day, todo: todo))

        let lateSameDay = day.addingTimeInterval(23 * 3600 + 59 * 60)
        #expect(todo.trackedMinutes(on: lateSameDay) == 60)
    }

    @Test("Export lists only todos with time on that day, alphabetically")
    func exportText() throws {
        let context = try makeContext()
        let zebra = Todo(title: "Zebra task")
        let apple = Todo(title: "Apple task")
        let untracked = Todo(title: "Nothing logged")
        let yesterdayOnly = Todo(title: "Yesterday only")
        for todo in [zebra, apple, untracked, yesterdayOnly] { context.insert(todo) }
        context.insert(TimeEntry(minutes: 120, day: day, todo: zebra))
        context.insert(TimeEntry(minutes: 60, day: day, todo: apple))
        context.insert(TimeEntry(minutes: 60, day: otherDay, todo: yesterdayOnly))

        let text = TimeExportService.text(for: [zebra, apple, untracked, yesterdayOnly], on: day)

        #expect(text == "- Apple task (1h)\n- Zebra task (2h)")
    }

    @Test("A day with nothing logged exports as empty, not as a stray newline")
    func exportTextEmpty() throws {
        let context = try makeContext()
        let todo = Todo(title: "Untracked")
        context.insert(todo)
        #expect(TimeExportService.text(for: [todo], on: day).isEmpty)
    }

    @Test("Deleting a todo takes its time entries with it")
    func cascadeDelete() throws {
        let context = try makeContext()
        let todo = Todo(title: "Doomed")
        context.insert(todo)
        context.insert(TimeEntry(minutes: 60, day: day, todo: todo))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 1)

        context.delete(todo)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 0)
    }
}

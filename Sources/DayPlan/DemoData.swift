import Foundation
import SwiftData

/// A sample day, used for screenshots. Seeding only happens when
/// `DAYPLAN_SEED_DEMO=1` is set and the store is empty, so it can never touch
/// real data. Pair it with `DAYPLAN_STORE_DIR` to keep the throwaway store out
/// of Application Support entirely:
///
///     DAYPLAN_STORE_DIR=/tmp/dayplan-demo DAYPLAN_SEED_DEMO=1 open -n DayPlan.app
///
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["DAYPLAN_SEED_DEMO"] == "1"
    }

    static func seedIfRequested(in context: ModelContext) {
        guard isRequested else { return }

        let existingLists = (try? context.fetchCount(FetchDescriptor<TodoList>())) ?? 0
        let existingTodos = (try? context.fetchCount(FetchDescriptor<Todo>())) ?? 0
        guard existingLists == 0 && existingTodos == 0 else { return }

        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        /// Completion times spread across the morning, so the Done section reads
        /// like a day that actually happened.
        func finished(_ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }

        let work = TodoList(name: "Work", colorName: "purple", sortIndex: 0)
        let personal = TodoList(name: "Personal", colorName: "green", sortIndex: 1)
        let side = TodoList(name: "Side Project", colorName: "teal", sortIndex: 2)
        for list in [work, personal, side] { context.insert(list) }

        // Today: nine todos, five of them done, so the arc sits just past the middle.
        let openToday: [(String, Priority, TodoList?, Int?, String)] = [
            ("Write the release notes for 1.1", .high, work, 0, "Mention the collapsible detail pane and the new keyboard shortcut."),
            ("Review Marta's pull request", .medium, work, 0, ""),
            ("Book the rehearsal room", .low, personal, 1, ""),
            ("Sketch the onboarding screen", .none, side, nil, "Two panels at most. Anything longer and nobody reads it.")
        ]
        for (title, priority, list, due, notes) in openToday {
            let todo = Todo(title: title, notes: notes, priority: priority,
                            dueDate: due.map(day), list: list)
            if due == nil { todo.addToDailyPlan(on: today) }
            context.insert(todo)
        }

        let doneToday: [(String, Priority, TodoList?, Date)] = [
            ("Fix the midnight rollover in the Today pane", .high, work, finished(11, 32)),
            ("Reply to the hosting invoice", .low, personal, finished(11, 45)),
            ("Merge the animation refactor", .medium, work, finished(12, 4)),
            ("Water the plants", .none, personal, finished(12, 19)),
            ("Export a backup", .none, nil, finished(14, 33))
        ]
        for (title, priority, list, at) in doneToday {
            let todo = Todo(title: title, notes: "", priority: priority, list: list)
            todo.addToDailyPlan(on: today)
            todo.isDone = true
            todo.completedAt = at
            context.insert(todo)
        }

        // Not in today's plan, so the other panes have something to show.
        let later: [(String, Priority, TodoList?, Int?)] = [
            ("Renew the developer certificate", .high, work, 3),
            ("Plan the offsite agenda", .medium, work, 6),
            ("Compare pension providers", .none, personal, 12),
            ("Try SwiftData history tracking", .low, side, nil),
            ("Read up on inspector column sizing", .none, side, nil),
            ("Call the landlord about the radiator", .medium, personal, -1)
        ]
        for (title, priority, list, due) in later {
            let todo = Todo(title: title, notes: "", priority: priority,
                            dueDate: due.map(day), list: list)
            // The overdue one would otherwise be pulled into today automatically.
            if let due, due < 0 { todo.removeFromDailyPlan(on: today) }
            context.insert(todo)
        }

        let archive: [(String, TodoList?, Int)] = [
            ("Ship 1.0 to TestFlight", work, 1),
            ("Register the domain", side, 2),
            ("Cancel the old subscription", personal, 4)
        ]
        for (title, list, daysAgo) in archive {
            let todo = Todo(title: title, notes: "", priority: .none, list: list)
            todo.isDone = true
            todo.completedAt = cal.date(byAdding: .hour, value: -daysAgo * 24 + 3, to: now)
            context.insert(todo)
        }

        try? context.save()
    }
}

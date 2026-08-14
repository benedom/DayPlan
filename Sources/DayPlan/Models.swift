import Foundation
import SwiftData
import SwiftUI

// MARK: - Priority

enum Priority: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Short marker shown in list rows ("!", "!!", "!!!" like Reminders).
    var marker: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Lists

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

    var color: Color { ListPalette.color(for: colorName) }
}

enum ListPalette {
    static let names = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "gray"]

    static func color(for name: String) -> Color {
        switch name {
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "gray": return .gray
        default: return .blue
        }
    }
}

// MARK: - Todos

@Model
final class Todo {
    var title: String = ""
    var notes: String = ""
    var priorityRaw: Int = 0
    /// Day-granular: always start of day, the time component carries no meaning.
    /// Write through `setDueDate(_:)` so it stays normalized.
    var dueDate: Date?
    var isDone: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()

    /// Day this todo was manually pinned into the daily plan (start of day).
    var pinnedDay: Date?
    /// Day this todo was manually kicked out of the daily plan (start of day).
    var excludedDay: Date?

    var list: TodoList?

    init(title: String,
         notes: String = "",
         priority: Priority = .none,
         dueDate: Date? = nil,
         list: TodoList? = nil) {
        self.title = title
        self.notes = notes
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        self.list = list
        self.isDone = false
        self.createdAt = Date()
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
}

// MARK: - Due date

extension Todo {
    /// Only the calendar day matters, so any picked time is snapped to start of day.
    func setDueDate(_ date: Date?) {
        dueDate = date.map { Calendar.current.startOfDay(for: $0) }
    }

    /// Old stores can still hold due dates with a time component, so flatten them once at launch.
    static func normalizeDueDates(in context: ModelContext) {
        let cal = Calendar.current
        guard let todos = try? context.fetch(FetchDescriptor<Todo>()) else { return }
        var changed = false
        for todo in todos {
            guard let due = todo.dueDate else { continue }
            let day = cal.startOfDay(for: due)
            if day != due {
                todo.dueDate = day
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}

// MARK: - Daily plan logic

extension Todo {
    /// Due today (or earlier, if overdue items should be pulled in) => automatically part of the day.
    func isAutoDaily(on day: Date, includeOverdue: Bool) -> Bool {
        guard let dueDate else { return false }
        let cal = Calendar.current
        if cal.isDate(dueDate, inSameDayAs: day) { return true }
        // A finished todo is never overdue, so it must not keep being dragged
        // forward into every following day's plan.
        guard !isDone else { return false }
        return includeOverdue && cal.startOfDay(for: dueDate) < cal.startOfDay(for: day)
    }

    func isInDailyPlan(on day: Date, includeOverdue: Bool) -> Bool {
        let cal = Calendar.current
        if let pinnedDay, cal.isDate(pinnedDay, inSameDayAs: day) { return true }
        if let excludedDay, cal.isDate(excludedDay, inSameDayAs: day) { return false }
        return isAutoDaily(on: day, includeOverdue: includeOverdue)
    }

    func addToDailyPlan(on day: Date) {
        pinnedDay = Calendar.current.startOfDay(for: day)
        excludedDay = nil
    }

    func removeFromDailyPlan(on day: Date) {
        excludedDay = Calendar.current.startOfDay(for: day)
        pinnedDay = nil
    }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: dueDate) < cal.startOfDay(for: Date())
    }

    func toggleDone() {
        isDone.toggle()
        completedAt = isDone ? Date() : nil
    }
}

// MARK: - Sorting

enum SortMode: String, CaseIterable, Identifiable {
    case smart = "Smart"
    case dueDate = "Due Date"
    case priority = "Priority"
    case title = "Title"
    case created = "Created"

    var id: String { rawValue }
}

enum TodoSorter {
    static func sort(_ todos: [Todo], by mode: SortMode) -> [Todo] {
        todos.sorted { a, b in
            // done items always sink to the bottom
            if a.isDone != b.isDone { return !a.isDone }
            switch mode {
            case .smart:
                let ad = a.dueDate.map { Calendar.current.startOfDay(for: $0) }
                let bd = b.dueDate.map { Calendar.current.startOfDay(for: $0) }
                if ad != bd {
                    switch (ad, bd) {
                    case let (x?, y?): return x < y
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: break
                    }
                }
                if a.priorityRaw != b.priorityRaw { return a.priorityRaw > b.priorityRaw }
                return a.createdAt < b.createdAt
            case .dueDate:
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return x == y ? a.createdAt < b.createdAt : x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.createdAt < b.createdAt
                }
            case .priority:
                if a.priorityRaw != b.priorityRaw { return a.priorityRaw > b.priorityRaw }
                return a.createdAt < b.createdAt
            case .title:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .created:
                return a.createdAt < b.createdAt
            }
        }
    }
}

// MARK: - Formatting helpers

enum DueFormatter {
    static func label(for date: Date, relativeTo today: Date) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let ref = cal.startOfDay(for: today)
        let diff = cal.dateComponents([.day], from: ref, to: day).day ?? 0
        let time = cal.dateComponents([.hour, .minute], from: date)
        let hasTime = !(time.hour == 0 && time.minute == 0)

        let dayPart: String
        switch diff {
        case 0: dayPart = "Today"
        case 1: dayPart = "Tomorrow"
        case -1: dayPart = "Yesterday"
        case 2...6:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            dayPart = f.string(from: date)
        default:
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            dayPart = f.string(from: date)
        }

        guard hasTime else { return dayPart }
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        return "\(dayPart), \(tf.string(from: date))"
    }
}

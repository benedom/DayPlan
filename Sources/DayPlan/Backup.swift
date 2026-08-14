import Foundation
import SwiftData

// MARK: - File format

/// Plain JSON on purpose: a backup is only worth something if it can be read
/// without the app that wrote it.
struct BackupDocument: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int = BackupDocument.currentFormatVersion
    var schemaVersion: String
    var appVersion: String
    var exportedAt: Date
    var lists: [BackupList]
    var todos: [BackupTodo]
    var timeEntries: [BackupTimeEntry] = []

    enum CodingKeys: String, CodingKey {
        case formatVersion, schemaVersion, appVersion, exportedAt, lists, todos, timeEntries
    }
}

struct BackupList: Codable {
    var id: UUID
    var name: String
    var colorName: String
    var sortIndex: Int
    var createdAt: Date
}

struct BackupTodo: Codable {
    /// Local to this file, just to let `BackupTimeEntry` reference its todo.
    var id: UUID = UUID()
    var title: String
    var notes: String
    var priorityRaw: Int
    var dueDate: Date?
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date
    var pinnedDay: Date?
    var excludedDay: Date?
    /// References `BackupList.id`; nil means the todo is unfiled.
    var listID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, priorityRaw, dueDate, isDone, completedAt
        case createdAt, pinnedDay, excludedDay, listID
    }
}

// Synthesized `Decodable` ignores default values: a missing key is `keyNotFound`,
// not "use the default". Every backup the shipped app wrote has no `id` and no
// `timeEntries`, so restore has to treat those as optional. `init(from:)` lives
// in extensions so the memberwise inits used on export stay synthesized.
extension BackupDocument {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Old files always wrote this, but the same default-value trap applies.
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        lists = try container.decode([BackupList].self, forKey: .lists)
        todos = try container.decode([BackupTodo].self, forKey: .todos)
        timeEntries = try container.decodeIfPresent([BackupTimeEntry].self, forKey: .timeEntries) ?? []
    }
}

extension BackupTodo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        priorityRaw = try container.decode(Int.self, forKey: .priorityRaw)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        pinnedDay = try container.decodeIfPresent(Date.self, forKey: .pinnedDay)
        excludedDay = try container.decodeIfPresent(Date.self, forKey: .excludedDay)
        listID = try container.decodeIfPresent(UUID.self, forKey: .listID)
    }
}

struct BackupTimeEntry: Codable {
    var minutes: Int
    var day: Date
    var createdAt: Date
    /// References `BackupTodo.id`.
    var todoID: UUID
}

// MARK: - Import options and results

enum ImportMode {
    /// Keep what is there, add what is missing.
    case merge
    /// Wipe the store, then restore the file verbatim.
    case replace
}

struct ImportSummary {
    var mode: ImportMode
    var listsCreated = 0
    var listsMatched = 0
    var todosCreated = 0
    var todosSkipped = 0
    var timeEntriesCreated = 0
}

enum BackupError: LocalizedError {
    case unsupportedFormat(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            return "This backup was written in format version \(version), which this version of DayPlan cannot read."
        }
    }
}

// MARK: - Service

enum BackupService {

    // MARK: Export

    static func exportData(from context: ModelContext) throws -> Data {
        let lists = try context.fetch(FetchDescriptor<TodoList>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        ))
        let todos = try context.fetch(FetchDescriptor<Todo>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))

        // Persistent identifiers are not stable across stores, so hand out fresh
        // ids just for this file and use them to wire todos back to their list.
        var ids: [PersistentIdentifier: UUID] = [:]
        let listDTOs = lists.map { list -> BackupList in
            let id = UUID()
            ids[list.persistentModelID] = id
            return BackupList(id: id,
                              name: list.name,
                              colorName: list.colorName,
                              sortIndex: list.sortIndex,
                              createdAt: list.createdAt)
        }

        var todoIDs: [PersistentIdentifier: UUID] = [:]
        let todoDTOs = todos.map { todo -> BackupTodo in
            let id = UUID()
            todoIDs[todo.persistentModelID] = id
            return BackupTodo(id: id,
                       title: todo.title,
                       notes: todo.notes,
                       priorityRaw: todo.priorityRaw,
                       dueDate: todo.dueDate,
                       isDone: todo.isDone,
                       completedAt: todo.completedAt,
                       createdAt: todo.createdAt,
                       pinnedDay: todo.pinnedDay,
                       excludedDay: todo.excludedDay,
                       listID: todo.list.flatMap { ids[$0.persistentModelID] })
        }

        let timeEntryDTOs = todos.flatMap { todo in
            todo.timeEntries.compactMap { entry -> BackupTimeEntry? in
                guard let todoID = todoIDs[todo.persistentModelID] else { return nil }
                return BackupTimeEntry(minutes: entry.minutes, day: entry.day, createdAt: entry.createdAt, todoID: todoID)
            }
        }

        let document = BackupDocument(
            schemaVersion: "\(DayPlanSchemaV2.versionIdentifier)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            exportedAt: Date(),
            lists: listDTOs,
            todos: todoDTOs,
            timeEntries: timeEntryDTOs
        )

        return try encoder.encode(document)
    }

    static func suggestedFileName(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "DayPlan Backup \(f.string(from: now)).json"
    }

    // MARK: Import

    @discardableResult
    static func restore(from data: Data, into context: ModelContext, mode: ImportMode) throws -> ImportSummary {
        let document = try decoder.decode(BackupDocument.self, from: data)
        guard document.formatVersion <= BackupDocument.currentFormatVersion else {
            throw BackupError.unsupportedFormat(document.formatVersion)
        }

        var summary = ImportSummary(mode: mode)

        if mode == .replace {
            // Object-by-object, not `delete(model:)`: a batch delete trips over the
            // mandatory inverse on `Todo.list` and fails the whole transaction.
            for todo in try context.fetch(FetchDescriptor<Todo>()) { context.delete(todo) }
            for list in try context.fetch(FetchDescriptor<TodoList>()) { context.delete(list) }
        }

        // Merging reuses a list of the same name rather than creating "Work" twice.
        var existingLists: [String: TodoList] = [:]
        if mode == .merge {
            for list in try context.fetch(FetchDescriptor<TodoList>()) {
                let key = list.name.lowercased()
                if existingLists[key] == nil { existingLists[key] = list }
            }
        }

        var resolved: [UUID: TodoList] = [:]
        var nextSortIndex = (try context.fetch(FetchDescriptor<TodoList>()).map(\.sortIndex).max() ?? -1) + 1

        for dto in document.lists {
            if let match = existingLists[dto.name.lowercased()] {
                resolved[dto.id] = match
                summary.listsMatched += 1
                continue
            }
            let list = TodoList(name: dto.name,
                                colorName: dto.colorName,
                                sortIndex: mode == .replace ? dto.sortIndex : nextSortIndex)
            list.createdAt = dto.createdAt
            context.insert(list)
            existingLists[dto.name.lowercased()] = list
            resolved[dto.id] = list
            nextSortIndex += 1
            summary.listsCreated += 1
        }

        // Re-importing the same file twice should not double every todo, but its
        // time entries still need somewhere to attach, so track the existing
        // todo behind each identity key rather than just whether it's taken.
        var existingByKey: [String: Todo] = [:]
        if mode == .merge {
            for todo in try context.fetch(FetchDescriptor<Todo>()) {
                existingByKey[identityKey(title: todo.title, createdAt: todo.createdAt)] = todo
            }
        }

        // Maps each DTO's file-local id to the live todo it resolved to, so
        // time entries below can find their todo regardless of whether it was
        // just created or already existed.
        var resolvedTodos: [UUID: Todo] = [:]

        for dto in document.todos {
            let key = identityKey(title: dto.title, createdAt: dto.createdAt)
            if mode == .merge, let existing = existingByKey[key] {
                resolvedTodos[dto.id] = existing
                summary.todosSkipped += 1
                continue
            }

            let todo = Todo(title: dto.title)
            todo.notes = dto.notes
            todo.priorityRaw = dto.priorityRaw
            todo.dueDate = dto.dueDate.map { Calendar.current.startOfDay(for: $0) }
            todo.isDone = dto.isDone
            todo.completedAt = dto.completedAt
            todo.createdAt = dto.createdAt
            todo.pinnedDay = dto.pinnedDay
            todo.excludedDay = dto.excludedDay
            todo.list = dto.listID.flatMap { resolved[$0] }
            context.insert(todo)
            resolvedTodos[dto.id] = todo
            if mode == .merge { existingByKey[key] = todo }
            summary.todosCreated += 1
        }

        // Re-importing the same file twice should not double every entry either.
        // The key includes the file-local todo id: duration + day + second is not
        // unique across todos (three "30m" logs in the same second would collide).
        var seenEntries = Set<String>()
        if mode == .merge {
            for (todoID, todo) in resolvedTodos {
                for entry in todo.timeEntries {
                    seenEntries.insert(timeEntryKey(todoID: todoID, minutes: entry.minutes, day: entry.day, createdAt: entry.createdAt))
                }
            }
        }

        for dto in document.timeEntries {
            guard let todo = resolvedTodos[dto.todoID] else { continue }
            let key = timeEntryKey(todoID: dto.todoID, minutes: dto.minutes, day: dto.day, createdAt: dto.createdAt)
            if mode == .merge, !seenEntries.insert(key).inserted { continue }

            let entry = TimeEntry(minutes: dto.minutes, day: dto.day, todo: todo)
            entry.createdAt = dto.createdAt
            context.insert(entry)
            summary.timeEntriesCreated += 1
        }

        try context.save()
        return summary
    }

    // MARK: Helpers

    /// Title plus creation instant is as close to an identity as the model gets.
    /// Seconds are truncated, not rounded: the file writes ISO8601 without
    /// fractional seconds, so rounding would miss about half of live dates
    /// on a merge re-import.
    private static func identityKey(title: String, createdAt: Date) -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalized)|\(Int(createdAt.timeIntervalSince1970))"
    }

    private static func timeEntryKey(todoID: UUID, minutes: Int, day: Date, createdAt: Date) -> String {
        "\(todoID)|\(minutes)|\(Int(day.timeIntervalSince1970))|\(Int(createdAt.timeIntervalSince1970))"
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

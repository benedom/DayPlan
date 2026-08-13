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
}

struct BackupList: Codable {
    var id: UUID
    var name: String
    var colorName: String
    var sortIndex: Int
    var createdAt: Date
}

struct BackupTodo: Codable {
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

        let todoDTOs = todos.map { todo in
            BackupTodo(title: todo.title,
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

        let document = BackupDocument(
            schemaVersion: "\(DayPlanSchemaV1.versionIdentifier)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            exportedAt: Date(),
            lists: listDTOs,
            todos: todoDTOs
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

        // Re-importing the same file twice should not double every todo.
        var seen = Set<String>()
        if mode == .merge {
            for todo in try context.fetch(FetchDescriptor<Todo>()) {
                seen.insert(identityKey(title: todo.title, createdAt: todo.createdAt))
            }
        }

        for dto in document.todos {
            let key = identityKey(title: dto.title, createdAt: dto.createdAt)
            if mode == .merge, !seen.insert(key).inserted {
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
            summary.todosCreated += 1
        }

        try context.save()
        return summary
    }

    // MARK: Helpers

    /// Title plus creation instant is as close to an identity as the model gets.
    private static func identityKey(title: String, createdAt: Date) -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalized)|\(Int(createdAt.timeIntervalSince1970.rounded()))"
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

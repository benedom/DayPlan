import Foundation
import SwiftData

// MARK: - Outcome

/// How the store came up. Anything other than `.opened` is worth telling the
/// user about. Silently starting empty looks exactly like "the app ate my data".
enum StoreOutcome {
    case opened
    /// The store on disk could not be opened, so it was moved aside and a fresh
    /// one was created. The user's bytes are still in `quarantine`.
    case recovered(quarantine: URL, error: Error)
    /// Not even a fresh store could be created. Running from memory, nothing
    /// entered in this session will survive a relaunch.
    case memoryOnly(error: Error)

    var needsAttention: Bool {
        if case .opened = self { return false }
        return true
    }
}

enum StoreLoadResult {
    case ready(ModelContainer, StoreOutcome)
    /// Even an in-memory container failed. The app can only show an error.
    case unavailable(Error)
}

// MARK: - Loader

enum StoreLoader {
    static let storeFileName = "DayPlan.store"

    /// Opens the store, degrading step by step instead of trapping:
    /// on-disk → quarantine and retry on disk → in-memory → report failure.
    static func load(at url: URL = storeURL()) -> StoreLoadResult {
        do {
            return .ready(try container(at: url), .opened)
        } catch let openError {
            // Unreadable, or a migration that could not run. Either way, never
            // delete: move the files somewhere the user can still get at them.
            if let quarantine = try? quarantineStore(at: url),
               let fresh = try? container(at: url) {
                return .ready(fresh, .recovered(quarantine: quarantine, error: openError))
            }

            // Disk is out. Let the app open anyway so the user can see why.
            let memory = ModelConfiguration(schema: .dayPlanCurrent, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: .dayPlanCurrent,
                                                   migrationPlan: DayPlanMigrationPlan.self,
                                                   configurations: memory) {
                return .ready(container, .memoryOnly(error: openError))
            }

            return .unavailable(openError)
        }
    }

    // MARK: Locations

    /// `DAYPLAN_STORE_DIR` points the app at a different store, which keeps a
    /// throwaway run (screenshots, a manual test) from ever opening the real one.
    static var supportDirectory: URL {
        let env = ProcessInfo.processInfo.environment["DAYPLAN_STORE_DIR"]
        if let path = env, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DayPlan", isDirectory: true)
    }

    static func storeURL() -> URL {
        let dir = supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(storeFileName)
    }

    // MARK: Internals

    private static func container(at url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(schema: .dayPlanCurrent, url: url)
        return try ModelContainer(for: .dayPlanCurrent,
                                  migrationPlan: DayPlanMigrationPlan.self,
                                  configurations: config)
    }

    /// Moves the store and its SQLite sidecars (-shm, -wal, …) into a timestamped
    /// folder next to it, and returns that folder.
    private static func quarantineStore(at url: URL) throws -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()

        let stamp = ISO8601DateFormatter.quarantineStamp.string(from: Date())
        let destination = dir
            .appendingPathComponent("Quarantined", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let siblings = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let storeFiles = siblings.filter { $0.lastPathComponent.hasPrefix(storeFileName) }
        guard !storeFiles.isEmpty else {
            // Nothing on disk to move, so retrying would just fail the same way.
            try? fm.removeItem(at: destination)
            throw CocoaError(.fileNoSuchFile)
        }

        for file in storeFiles {
            try fm.moveItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
        return destination
    }
}

private extension ISO8601DateFormatter {
    /// Colons are legal in HFS+/APFS paths but confuse people in Finder, so drop them.
    static let quarantineStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
        f.timeZone = .current
        return f
    }()
}

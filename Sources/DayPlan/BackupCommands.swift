import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Menu commands

struct BackupCommands: Commands {
    /// Nil when the store could not be opened. The items stay visible but dead,
    /// which reads better than a File menu that changes shape.
    let context: ModelContext?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button("Export Backup…") {
                if let context { BackupUI.export(from: context) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(context == nil)

            Menu("Import Backup") {
                Button("Merge Into Current Todos…") {
                    if let context { BackupUI.importBackup(into: context, mode: .merge) }
                }
                Button("Replace All Todos…") {
                    if let context { BackupUI.importBackup(into: context, mode: .replace) }
                }
            }
            .disabled(context == nil)

            Button("Show Data Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([StoreLoader.storeURL()])
            }
        }
    }
}

// MARK: - Panels

@MainActor
enum BackupUI {

    static func export(from context: ModelContext) {
        // Encode before asking for a destination: failing after the user picked
        // a file just leaves a confusing empty file behind.
        let data: Data
        do {
            data = try BackupService.exportData(from: context)
        } catch {
            report(error, title: "Export Failed")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export DayPlan Backup"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = BackupService.suggestedFileName()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            report(error, title: "Export Failed")
        }
    }

    static func importBackup(into context: ModelContext, mode: ImportMode) {
        let panel = NSOpenPanel()
        panel.title = mode == .replace ? "Replace All Todos From Backup" : "Merge Backup Into Current Todos"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if mode == .replace, !confirmReplace(fileName: url.lastPathComponent) { return }

        do {
            let data = try Data(contentsOf: url)
            let summary = try BackupService.restore(from: data, into: context, mode: mode)
            reportSuccess(summary)
        } catch {
            report(error, title: "Import Failed")
        }
    }

    // MARK: Alerts

    private static func confirmReplace(fileName: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Replace all todos with “\(fileName)”?"
        alert.informativeText = "Every list and todo currently in DayPlan is deleted first. This can’t be undone, so export a backup if you aren’t sure."
        alert.addButton(withTitle: "Replace All")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func reportSuccess(_ summary: ImportSummary) {
        var lines = ["\(summary.todosCreated) todo(s) imported."]
        if summary.listsCreated > 0 { lines.append("\(summary.listsCreated) list(s) created.") }
        if summary.listsMatched > 0 { lines.append("\(summary.listsMatched) list(s) matched by name.") }
        if summary.todosSkipped > 0 { lines.append("\(summary.todosSkipped) todo(s) skipped as duplicates.") }

        let alert = NSAlert()
        alert.messageText = summary.mode == .replace ? "Backup Restored" : "Backup Merged"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func report(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

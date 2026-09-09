import AppKit
import SwiftData
import SwiftUI

// MARK: - Text generation

enum TimeExportService {
    /// One line per todo with tracked time on `day`, ready to paste into a
    /// timesheet: "- Todo title (2h)". Todos without tracked time that day are
    /// left out, and results are alphabetical for a stable, scannable order.
    static func text(for todos: [Todo], on day: Date) -> String {
        todos
            .map { ($0, $0.trackedMinutes(on: day)) }
            .filter { $0.1 > 0 }
            .sorted { $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending }
            .map { "- \($0.0.title) (\(TimeFormatter.hoursLabel(minutes: $0.1)))" }
            .joined(separator: "\n")
    }
}

// MARK: - Sheet

struct TimeExportSheet: View {
    let listTitle: String
    /// `nil` means the unfiled "No List" todos. Read live via `@Query` so a
    /// time log added while this sheet is open still appears in the preview.
    let listID: PersistentIdentifier?

    @Query private var todos: [Todo]
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var copyState: CopyState = .idle

    private enum CopyState { case idle, copied, failed }

    init(listTitle: String, listID: PersistentIdentifier?, day: Date) {
        self.listTitle = listTitle
        self.listID = listID
        _day = State(initialValue: day)
    }

    private var scopedTodos: [Todo] {
        if let listID {
            return todos.filter { $0.list?.persistentModelID == listID }
        }
        return todos.filter { $0.list == nil }
    }

    private var text: String { TimeExportService.text(for: scopedTodos, on: day) }

    var body: some View {
        // Computed once per pass: `text` walks every todo, and the body reads it
        // four times (preview, styling, the Copy button's enablement, onChange).
        let text = text
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Tracked Time").font(.headline)
                Text(listTitle).font(.subheadline).foregroundStyle(.secondary)
            }

            DatePicker("Day", selection: $day, displayedComponents: .date)
                .datePickerStyle(.compact)

            ScrollView {
                Text(text.isEmpty ? "No tracked time on this day." : text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 140, maxHeight: 220)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                switch copyState {
                case .idle:
                    EmptyView()
                case .copied:
                    Label("Copied to Clipboard", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                case .failed:
                    Label("Couldn’t copy to the clipboard.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
                Spacer()
                Button("Close") { dismiss() }
                Button("Copy to Clipboard") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    // Only claim success if the write actually landed: another
                    // app can be holding the pasteboard, and silently showing
                    // "Copied" would send the user to paste nothing.
                    let written = pasteboard.setString(text, forType: .string)
                    withAnimation(Motion.snap) { copyState = written ? .copied : .failed }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onChange(of: text) { _, _ in copyState = .idle }
    }
}

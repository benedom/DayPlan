import SwiftUI
import SwiftData

enum DayPlanWindow {
    static let main = "main"
}

extension Notification.Name {
    static let newTodoRequested = Notification.Name("DayPlan.newTodoRequested")
    static let newListRequested = Notification.Name("DayPlan.newListRequested")
}

@main
struct DayPlanApp: App {
    private let store: StoreLoadResult

    init() {
        store = StoreLoader.load()
        if case .ready(let container, _) = store {
            DemoData.seedIfRequested(in: container.mainContext)
            Todo.normalizeDueDates(in: container.mainContext)
        }
    }

    private var context: ModelContext? {
        if case .ready(let container, _) = store { return container.mainContext }
        return nil
    }

    var body: some Scene {
        WindowGroup(id: DayPlanWindow.main) {
            StoreHost(store: store) { outcome in
                RootView(storeOutcome: outcome)
            } fallback: { error in
                StoreFailureView(error: error)
            }
            .frame(minWidth: 820, minHeight: 460)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Todo") {
                    NotificationCenter.default.post(name: .newTodoRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New List") {
                    NotificationCenter.default.post(name: .newListRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            BackupCommands(context: context)
        }

        // Same process, same container as the window above, so the menu bar list
        // and the app stay in sync without any shared-store plumbing.
        MenuBarExtra {
            StoreHost(store: store) { _ in
                MenuBarView()
            } fallback: { error in
                StoreFailureView(error: error).frame(width: 340)
            }
        } label: {
            StoreHost(store: store) { _ in
                MenuBarLabel()
            } fallback: { _ in
                Image(systemName: "exclamationmark.triangle.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Store host

/// `SceneBuilder` has no conditionals, so the branch between "store is up" and
/// "store could not be opened" happens here, one level down in the view tree.
private struct StoreHost<Content: View, Fallback: View>: View {
    let store: StoreLoadResult
    @ViewBuilder let content: (StoreOutcome) -> Content
    @ViewBuilder let fallback: (Error) -> Fallback

    var body: some View {
        switch store {
        case .ready(let container, let outcome):
            content(outcome)
                .modelContainer(container)
        case .unavailable(let error):
            fallback(error)
        }
    }
}

// MARK: - Failure UI

/// Last-resort screen: no store at all. Says what happened and points at the
/// files, instead of trapping on launch with nothing on screen.
struct StoreFailureView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("DayPlan Can’t Open Its Database")
                .font(.title3.bold())

            Text("Your todos are still on disk. DayPlan just can’t read them right now, and nothing has been deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(error.localizedDescription)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal)

            HStack {
                Button("Show Data Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([StoreLoader.storeURL()])
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 460)
        .padding(28)
    }
}

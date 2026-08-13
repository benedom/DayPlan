import SwiftUI
import SwiftData

// MARK: - Menu bar label

/// The thing that actually sits in the system menu bar: icon plus the number of
/// open todos for today. Lives in its own view so `@Query` keeps it current.
struct MenuBarLabel: View {
    @Query private var todos: [Todo]

    @AppStorage("includeOverdue") private var includeOverdue = true

    var body: some View {
        let open = todos.filter {
            !$0.isDone && $0.isInDailyPlan(on: Calendar.current.startOfDay(for: Date()),
                                           includeOverdue: includeOverdue)
        }.count

        HStack(spacing: 3) {
            Image(systemName: "checklist")
                // Nods whenever the number of open todos changes.
                .symbolEffect(.bounce, value: open)
            if open > 0 {
                Text("\(open)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(value: Double(open)))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .animation(Motion.snap, value: open)
    }
}

// MARK: - Popover

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    @Query private var todos: [Todo]

    @AppStorage("includeOverdue") private var includeOverdue = true
    @AppStorage("menuBarShowDone") private var showDone = true
    @AppStorage("sortMode") private var sortMode: SortMode = .smart

    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var contentHeight: CGFloat = 0
    /// Flipped on once the popover is on screen, so the content eases in
    /// instead of appearing fully formed.
    @State private var appeared = false

    private let midnightTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if openTodos.isEmpty && doneTodos.isEmpty {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(openTodos.enumerated()), id: \.element.persistentModelID) { index, todo in
                            MenuBarTodoRow(todo: todo, today: today, index: index)
                                .transition(Motion.rowTransition)
                        }

                        if !doneTodos.isEmpty {
                            doneHeader
                                .transition(.opacity)
                            if showDone {
                                ForEach(Array(doneTodos.enumerated()), id: \.element.persistentModelID) { index, todo in
                                    MenuBarTodoRow(todo: todo, today: today, index: index)
                                        .transition(Motion.rowTransition)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    // A ScrollView has no intrinsic height inside a menu bar window,
                    // so it collapses to nothing. Measure the content and size it.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(max(contentHeight, 1), 360))
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: .top)
        .task {
            withAnimation(Motion.appear) { appeared = true }
        }
        // Rows slide in and out as todos get checked off, added, or roll over
        // to a new day; the disclosure section grows and shrinks with them.
        .animation(Motion.list, value: rowKey)
        .animation(Motion.reveal, value: showDone)
        .onReceive(midnightTicker) { _ in
            let now = Calendar.current.startOfDay(for: Date())
            if now != today { today = now }
        }
    }

    /// Identity of everything currently listed. Changes exactly when a row is
    /// added, removed, or moves between the open and done sections.
    private var rowKey: [PersistentIdentifier] {
        openTodos.map(\.persistentModelID) + doneTodos.map(\.persistentModelID)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Today").font(.headline)
                Text(dateLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(openTodos.count) open")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(openTodos.count)))
                .animation(Motion.snap, value: openTodos.count)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var doneHeader: some View {
        Button {
            withAnimation(Motion.reveal) { showDone.toggle() }
        } label: {
            HStack(spacing: 4) {
                // One chevron that turns, rather than two that swap. The
                // rotation reads as the section opening.
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(showDone ? 90 : 0))
                    .animation(Motion.snap, value: showDone)
                Text("Done · \(doneTodos.count)")
                    .font(.caption.bold())
                    .contentTransition(.numericText(value: Double(doneTodos.count)))
                    .animation(Motion.snap, value: doneTodos.count)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, openTodos.isEmpty ? 4 : 10)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sun.max")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
                .symbolEffect(.breathe)
            Text("Nothing planned for today")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openMainWindow()
            } label: {
                Label("Open DayPlan", systemImage: "arrow.up.forward.app")
                    .font(.callout)
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .hoverLift(1.04)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(PressableStyle())
            .hoverLift()
            .foregroundStyle(.secondary)
            .help("Quit DayPlan")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Data

    private var dailyTodos: [Todo] {
        todos.filter { $0.isInDailyPlan(on: today, includeOverdue: includeOverdue) }
    }

    private var openTodos: [Todo] {
        TodoSorter.sort(dailyTodos.filter { !$0.isDone }, by: sortMode)
    }

    /// Done items of the day: finished today, or explicitly part of today’s plan.
    private var doneTodos: [Todo] {
        let cal = Calendar.current
        return todos
            .filter { todo in
                guard todo.isDone else { return false }
                if let completedAt = todo.completedAt, cal.isDate(completedAt, inSameDayAs: today) {
                    return true
                }
                return todo.isInDailyPlan(on: today, includeOverdue: includeOverdue)
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: today)
    }

    // MARK: Actions

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: DayPlanWindow.main)
    }
}

// MARK: - Row

private struct MenuBarTodoRow: View {
    @Bindable var todo: Todo
    let today: Date
    /// Position in its section, only used to stagger the entrance.
    var index: Int = 0

    @State private var hovering = false
    @State private var shown = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CompletionToggle(todo: todo, size: 14)

            VStack(alignment: .leading, spacing: 2) {
                // Baseline-aligned: a two-line title must not push the priority
                // marker down to the middle of the row.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if todo.priority != .none {
                        Text(todo.priority.marker)
                            .font(.caption.bold())
                            .foregroundStyle(todo.priority.color)
                            .transition(.scale.combined(with: .opacity))
                    }
                    TodoTitleText(title: todo.title, isDone: todo.isDone)
                        .font(.callout)
                }
                .animation(Motion.snap, value: todo.priority)

                HStack(spacing: 8) {
                    if let due = todo.dueDate, !todo.isDone {
                        Label(DueFormatter.label(for: due, relativeTo: today), systemImage: "calendar")
                            .foregroundStyle(todo.isOverdue ? Color.red : .secondary)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    if let list = todo.list {
                        Label(list.name, systemImage: "circle.fill")
                            .labelStyle(ListBadgeStyle(color: list.color))
                    }
                }
                .font(.caption)
                .animation(Motion.snap, value: todo.isDone)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(hovering ? 0.12 : 0))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        // Staggered entrance: rows cascade instead of all arriving at once.
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 6)
        .task {
            withAnimation(Motion.list.delay(min(Double(index) * 0.035, 0.3))) { shown = true }
        }
    }
}

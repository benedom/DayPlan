import SwiftUI
import SwiftData

struct TodoListPane: View {
    let title: String
    let subtitle: String
    let todos: [Todo]
    let today: Date
    let includeOverdue: Bool
    let showsListBadge: Bool
    let showsCompletionDate: Bool
    let isTodayPane: Bool
    let allowsQuickAdd: Bool
    /// Today’s plan as a whole, deliberately *not* derived from `todos`, which
    /// is already narrowed by the search field and the “Show Completed” toggle.
    let dailyDone: Int
    let dailyTotal: Int

    @Binding var selection: PersistentIdentifier?
    @Binding var showsDetail: Bool
    /// False when there is nothing the toggle could open: no selection and no
    /// previous one left in this pane.
    let canShowDetail: Bool
    @Binding var sortMode: SortMode
    @Binding var showCompleted: Bool
    @Binding var includeOverdueSetting: Bool

    let onCreate: (String) -> Void
    let onDelete: (Todo) -> Void

    /// Today's Done section stays open by default, since hiding it would put the
    /// finished todos right back where they were.
    @AppStorage("showTodayDone") private var showTodayDone = true

    @State private var draft = ""
    /// Bumped on every created todo so the plus icon can bounce.
    @State private var created = 0
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if isTodayPane && dailyTotal > 0 {
                DayArcView(done: dailyDone, total: dailyTotal)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            Divider()
            if allowsQuickAdd {
                quickAdd
                Divider()
            }
            if todos.isEmpty {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                list
                    .transition(.opacity)
            }
        }
        .animation(Motion.list, value: rowKey)
        .animation(Motion.reveal, value: dailyTotal > 0)
        // Escape is the fastest way back to a full-width list.
        .onExitCommand {
            if selection != nil {
                withAnimation(Motion.reveal) { selection = nil }
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $sortMode) {
                        ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    // Today has its own Done section, so the global toggle
                    // would be a second control for the same thing.
                    if !showsCompletionDate && !isTodayPane {
                        Toggle("Show Completed", isOn: $showCompleted)
                    }
                    if isTodayPane {
                        Toggle("Pull In Overdue Todos", isOn: $includeOverdueSetting)
                    }
                } label: {
                    Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem {
                Button {
                    draftFocused = true
                } label: {
                    Label("New Todo", systemImage: "plus")
                }
                .help("New Todo (⌘N)")
                .disabled(!allowsQuickAdd)
            }
            ToolbarItem {
                Button {
                    showsDetail.toggle()
                } label: {
                    Label(showsDetail ? "Hide Details" : "Show Details",
                          systemImage: "sidebar.trailing")
                        .symbolVariant(showsDetail ? .fill : .none)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(showsDetail ? "Hide Details (⌥⌘I)" : "Show Details (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(!canShowDetail)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTodoRequested)) { _ in
            if allowsQuickAdd { draftFocused = true }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        // Switching panes cross-fades the heading instead of hard-cutting it.
        .id(title)
        .transition(.blurReplace.combined(with: .offset(y: 4)))
        .animation(Motion.reveal, value: title)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
                // Spins a quarter turn and grows while the field has focus,
                // and kicks once each time a todo is actually created.
                .rotationEffect(.degrees(draftFocused ? 90 : 0))
                .scaleEffect(draftFocused ? 1.12 : 1)
                .symbolEffect(.bounce, value: created)
                .animation(Motion.snap, value: draftFocused)
            TextField(isTodayPane ? "Add to today…" : "Add a todo…", text: $draft)
                .textFieldStyle(.plain)
                .focused($draftFocused)
                .onSubmit {
                    guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    withAnimation(Motion.list) { onCreate(draft) }
                    draft = ""
                    created += 1
                    draftFocused = true
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(draftFocused ? 0.55 : 0.35))
        .overlay(alignment: .bottom) {
            // Accent underline that wipes in from the leading edge on focus.
            Rectangle()
                .fill(.tint)
                .frame(height: 2)
                .scaleEffect(x: draftFocused ? 1 : 0, anchor: .leading)
                .opacity(draftFocused ? 1 : 0)
        }
        .animation(Motion.reveal, value: draftFocused)
    }

    /// Changes when a row is added, removed, or crosses between the open and
    /// done sections. Ticking a todo off keeps the same set of IDs, so the
    /// section it lives in has to be part of the key.
    private var rowKey: [PersistentIdentifier] {
        openTodos.map(\.persistentModelID) + doneTodos.map(\.persistentModelID)
    }

    /// Today splits its rows; every other pane shows one flat run.
    private var openTodos: [Todo] {
        isTodayPane ? todos.filter { !$0.isDone } : todos
    }

    /// Newest completion first, because reading back the day works better in reverse.
    private var doneTodos: [Todo] {
        guard isTodayPane else { return [] }
        return todos.filter(\.isDone).sorted {
            ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(openTodos) { todo in
                row(for: todo)
            }

            if !doneTodos.isEmpty {
                Section {
                    if showTodayDone {
                        ForEach(doneTodos) { todo in
                            // Completion time replaces the due date here: once
                            // it's done, "when did I finish it" is the question.
                            row(for: todo, showsCompletionDate: true)
                                .transition(Motion.rowTransition)
                        }
                    }
                } header: {
                    doneSectionHeader
                }
            }
        }
        .animation(Motion.reveal, value: showTodayDone)
        .listStyle(.inset)
        .onDeleteCommand {
            if let selection, let todo = todos.first(where: { $0.persistentModelID == selection }) {
                onDelete(todo)
            }
        }
    }

    private func row(for todo: Todo, showsCompletionDate override: Bool? = nil) -> some View {
        TodoRow(
            todo: todo,
            today: today,
            includeOverdue: includeOverdue,
            showsListBadge: showsListBadge,
            showsCompletionDate: override ?? showsCompletionDate
        )
        .tag(todo.persistentModelID)
        .contextMenu {
            rowMenu(for: todo)
        }
    }

    /// Same disclosure affordance as the menu bar popover: one chevron that
    /// turns, rather than two that swap.
    private var doneSectionHeader: some View {
        Button {
            withAnimation(Motion.reveal) { showTodayDone.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(showTodayDone ? 90 : 0))
                    .animation(Motion.snap, value: showTodayDone)
                Text("Done · \(doneTodos.count)")
                    .contentTransition(.numericText(value: Double(doneTodos.count)))
                    .animation(Motion.snap, value: doneTodos.count)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowMenu(for todo: Todo) -> some View {
        Button(todo.isDone ? "Mark as Not Done" : "Mark as Done") { todo.toggleDone() }

        if todo.isInDailyPlan(on: today, includeOverdue: includeOverdue) {
            Button("Remove from Today") { todo.removeFromDailyPlan(on: today) }
        } else {
            Button("Add to Today") { todo.addToDailyPlan(on: today) }
        }

        Menu("Priority") {
            ForEach(Priority.allCases) { p in
                Button {
                    todo.priority = p
                } label: {
                    Label(p.label, systemImage: todo.priority == p ? "checkmark" : "")
                }
            }
        }

        Menu("Due Date") {
            Button("Today") { todo.setDueDate(today) }
            Button("Tomorrow") {
                todo.setDueDate(Calendar.current.date(byAdding: .day, value: 1, to: today))
            }
            Button("Next Week") {
                todo.setDueDate(Calendar.current.date(byAdding: .day, value: 7, to: today))
            }
            Divider()
            Button("None") { todo.setDueDate(nil) }
        }

        Divider()
        Button("Delete", role: .destructive) { onDelete(todo) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: isTodayPane ? "sun.max" : "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
                .symbolEffect(.breathe)
            Text(isTodayPane ? "Nothing planned for today"
                 : showsCompletionDate ? "Nothing completed yet"
                 : "No todos here")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(isTodayPane
                 ? "Todos due today land here automatically. Add others from any list with “Add to Today”."
                 : showsCompletionDate ? "Finished todos collect here, newest first."
                 : "Type above to add one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct TodoRow: View {
    @Bindable var todo: Todo
    let today: Date
    let includeOverdue: Bool
    let showsListBadge: Bool
    var showsCompletionDate: Bool = false

    /// Bumped when the todo joins today’s plan, so the sun can bounce.
    @State private var sunPulse = 0

    private var inDaily: Bool { todo.isInDailyPlan(on: today, includeOverdue: includeOverdue) }

    private var notesPreview: String {
        todo.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompletionToggle(todo: todo)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if todo.priority != .none {
                        Text(todo.priority.marker)
                            .font(.caption.bold())
                            .foregroundStyle(todo.priority.color)
                            .transition(.scale.combined(with: .opacity))
                    }
                    TodoTitleText(title: todo.title, isDone: todo.isDone)
                }
                .animation(Motion.snap, value: todo.priority)

                HStack(spacing: 8) {
                    if showsCompletionDate, let done = todo.completedAt {
                        Label(DueFormatter.label(for: done, relativeTo: today), systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else if let due = todo.dueDate {
                        Label(DueFormatter.label(for: due, relativeTo: today), systemImage: "calendar")
                            .foregroundStyle(todo.isOverdue ? Color.red : .secondary)
                    }
                    if showsListBadge {
                        if let list = todo.list {
                            Label(list.name, systemImage: "circle.fill")
                                .labelStyle(ListBadgeStyle(color: list.color))
                        } else {
                            Label("No List", systemImage: "circle.dashed")
                                .labelStyle(ListBadgeStyle(color: .secondary, iconSize: 9))
                        }
                    }
                    if !notesPreview.isEmpty {
                        Label("Note", systemImage: "note.text")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .help(notesPreview)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .font(.caption)
                .animation(Motion.snap, value: todo.dueDate)
                .animation(Motion.snap, value: notesPreview.isEmpty)
            }

            Spacer(minLength: 4)

            Button {
                withAnimation(Motion.snap) {
                    if inDaily {
                        todo.removeFromDailyPlan(on: today)
                    } else {
                        todo.addToDailyPlan(on: today)
                    }
                }
                if inDaily { sunPulse += 1 }
            } label: {
                Image(systemName: inDaily ? "sun.max.fill" : "sun.max")
                    .foregroundStyle(inDaily ? Color.orange : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: sunPulse)
                    .rotationEffect(.degrees(inDaily ? 0 : -30))
                    .animation(Motion.snap, value: inDaily)
            }
            .buttonStyle(PressableStyle())
            .hoverLift(1.18)
            .help(inDaily ? "Remove from today’s plan" : "Add to today’s plan")
        }
        .padding(.vertical, 3)
    }
}

struct ListBadgeStyle: LabelStyle {
    let color: Color
    var iconSize: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: iconSize))
                .foregroundStyle(color)
            configuration.title
                .foregroundStyle(.secondary)
        }
    }
}

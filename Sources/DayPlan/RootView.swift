import SwiftUI
import SwiftData

enum Route: Hashable {
    case today
    case all
    case completed
    case noList
    case list(PersistentIdentifier)
}

struct RootView: View {
    var storeOutcome: StoreOutcome = .opened

    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\TodoList.sortIndex), SortDescriptor(\TodoList.createdAt)])
    private var lists: [TodoList]

    @Query private var todos: [Todo]

    @State private var route: Route? = .today
    @State private var selectedTodoID: PersistentIdentifier?
    /// Survives a deselection so the detail pane can be toggled back open on the
    /// same todo instead of only ever closing.
    @State private var lastSelectedTodoID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var today = Calendar.current.startOfDay(for: Date())

    @State private var renamingList: TodoList?
    @State private var renameText = ""
    @State private var listPendingDeletion: TodoList?
    @State private var showStoreAlert = false

    @AppStorage("includeOverdue") private var includeOverdue = true
    @AppStorage("showCompleted") private var showCompleted = false
    @AppStorage("sortMode") private var sortMode: SortMode = .smart

    private let midnightTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var current: Route { route ?? .today }

    // MARK: Body

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            TodoListPane(
                title: paneTitle,
                subtitle: paneSubtitle,
                todos: visibleTodos,
                today: today,
                includeOverdue: includeOverdue,
                showsListBadge: showsListBadge,
                showsCompletionDate: isCompletedPane,
                isTodayPane: isTodayPane,
                allowsQuickAdd: !isCompletedPane,
                dailyDone: dailyTodos.filter(\.isDone).count,
                dailyTotal: dailyTodos.count,
                selection: $selectedTodoID,
                showsDetail: showsDetail,
                canShowDetail: selectedTodoID != nil || restorableTodoID != nil,
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                includeOverdueSetting: $includeOverdue,
                onCreate: addTodo(titled:),
                onDelete: delete(_:)
            )
            .frame(minWidth: 320)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search todos")
            // The detail pane is only on screen while something is selected, so
            // it gives its width back the moment the todo is deselected.
            .inspector(isPresented: showsDetail) {
                TodoDetailPane(
                    todo: selectedTodo,
                    lists: lists,
                    today: today,
                    includeOverdue: includeOverdue,
                    onClose: { showsDetail.wrappedValue = false },
                    onDelete: delete(_:)
                )
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
            }
        }
        .task { seedIfNeeded() }
        .onChange(of: selectedTodoID) { _, new in
            if let new { lastSelectedTodoID = new }
        }
        .onReceive(midnightTicker) { _ in
            let now = Calendar.current.startOfDay(for: Date())
            if now != today { today = now }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newListRequested)) { _ in
            addList()
        }
        .onChange(of: route) { _, _ in
            withAnimation(Motion.reveal) { selectedTodoID = nil }
            // Reopening the detail pane in another pane should never resurrect a
            // todo that isn't even in the list you're looking at.
            lastSelectedTodoID = nil
        }
        .alert("Rename List", isPresented: Binding(
            get: { renamingList != nil },
            set: { if !$0 { renamingList = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingList = nil }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { renamingList?.name = trimmed }
                renamingList = nil
            }
        }
        .confirmationDialog(
            "Delete “\(listPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { listPendingDeletion != nil },
                set: { if !$0 { listPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete List and \(listPendingDeletion?.todos.count ?? 0) Todo(s)", role: .destructive) {
                if let list = listPendingDeletion {
                    if case .list(let id) = current, id == list.persistentModelID { route = .today }
                    context.delete(list)
                }
                listPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { listPendingDeletion = nil }
        } message: {
            Text("Todos in this list are deleted as well. This can’t be undone.")
        }
        .task { showStoreAlert = storeOutcome.needsAttention }
        .alert(storeAlertTitle, isPresented: $showStoreAlert) {
            if case .recovered(let quarantine, _) = storeOutcome {
                Button("Show Recovered Files") {
                    NSWorkspace.shared.activateFileViewerSelecting([quarantine])
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(storeAlertMessage)
        }
    }

    // MARK: Store health

    private var storeAlertTitle: String {
        switch storeOutcome {
        case .opened: return ""
        case .recovered: return "DayPlan Started With an Empty Database"
        case .memoryOnly: return "Changes Won’t Be Saved"
        }
    }

    private var storeAlertMessage: String {
        switch storeOutcome {
        case .opened:
            return ""
        case .recovered(_, let error):
            return """
            The previous database could not be opened, so it was moved to a “Quarantined” folder \
            and DayPlan started fresh. Nothing was deleted, and you can restore an export with \
            File ▸ Import Backup.

            \(error.localizedDescription)
            """
        case .memoryOnly(let error):
            return """
            DayPlan couldn’t write to its data folder, so it is running from memory: everything \
            you add now is gone when you quit. Export a backup before quitting if you want to keep it.

            \(error.localizedDescription)
            """
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $route) {
            Section("Planning") {
                sidebarRow(
                    route: .today,
                    icon: "sun.max.fill",
                    tint: .orange,
                    title: "Today",
                    count: openCount(in: dailyTodos)
                )
                sidebarRow(
                    route: .all,
                    icon: "tray.full.fill",
                    tint: .indigo,
                    title: "All Todos",
                    count: openCount(in: todos)
                )
                sidebarRow(
                    route: .completed,
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    title: "Completed",
                    count: completedTodos.count
                )
            }

            Section("Lists") {
                sidebarRow(
                    route: .noList,
                    icon: "circle.dashed",
                    tint: .secondary,
                    title: "No List",
                    count: openCount(in: unassignedTodos)
                )

                ForEach(lists) { list in
                    sidebarRow(
                        route: .list(list.persistentModelID),
                        icon: "circle.fill",
                        tint: list.color,
                        title: list.name,
                        count: openCount(in: list.todos)
                    )
                    .contextMenu {
                        Button("Rename…") {
                            renameText = list.name
                            renamingList = list
                        }
                        Menu("Color") {
                            ForEach(ListPalette.names, id: \.self) { name in
                                Button {
                                    list.colorName = name
                                } label: {
                                    Label(name.capitalized, systemImage: list.colorName == name ? "checkmark" : "circle.fill")
                                }
                            }
                        }
                        Divider()
                        Button("Delete List…", role: .destructive) { listPendingDeletion = list }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(Motion.list, value: lists.map(\.persistentModelID))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    addList()
                } label: {
                    Label("Add List", systemImage: "plus.circle")
                }
                .buttonStyle(.accessoryBar)
                .hoverLift(1.03)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func sidebarRow(route target: Route, icon: String, tint: Color, title: String, count: Int) -> some View {
        Label {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        // Counts roll like an odometer instead of blinking.
                        .contentTransition(.numericText(value: Double(count)))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .animation(Motion.snap, value: count)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(icon == "circle.fill" ? .caption : .body)
                .frame(width: 16)
                .symbolEffect(.bounce, value: count)
        }
        .tag(target)
    }

    // MARK: Data

    private var dailyTodos: [Todo] {
        todos.filter { $0.isInDailyPlan(on: today, includeOverdue: includeOverdue) }
    }

    private var completedTodos: [Todo] {
        todos.filter { $0.isDone }
    }

    private var unassignedTodos: [Todo] {
        todos.filter { $0.list == nil }
    }

    private var visibleTodos: [Todo] {
        var base: [Todo]
        switch current {
        case .today:
            base = dailyTodos
        case .all:
            base = todos
        case .completed:
            base = completedTodos
        case .noList:
            base = unassignedTodos
        case .list(let id):
            base = todos.filter { $0.list?.persistentModelID == id }
        }
        // Today always carries its finished todos along. The pane files them
        // into a collapsible "Done" section instead of hiding them, so the day
        // can be read back without a detour through the Completed pane.
        if !showCompleted && !isCompletedPane && !isTodayPane { base = base.filter { !$0.isDone } }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            base = base.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.notes.localizedCaseInsensitiveContains(query)
            }
        }
        if isCompletedPane {
            // Most recently finished first, the only ordering that makes sense here.
            return base.sorted {
                ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
            }
        }
        return TodoSorter.sort(base, by: sortMode)
    }

    private var selectedTodo: Todo? {
        guard let selectedTodoID else { return nil }
        return todos.first { $0.persistentModelID == selectedTodoID }
    }

    /// Showing the detail pane and having a todo selected are the same state.
    /// Routing both through the selection means closing the pane deselects, and
    /// clicking the row again brings it straight back.
    private var showsDetail: Binding<Bool> {
        Binding(
            get: { selectedTodoID != nil },
            set: { shown in
                withAnimation(Motion.reveal) {
                    selectedTodoID = shown ? restorableTodoID : nil
                }
            }
        )
    }

    /// The last selection, but only while it is still on screen in this pane.
    private var restorableTodoID: PersistentIdentifier? {
        guard let lastSelectedTodoID,
              visibleTodos.contains(where: { $0.persistentModelID == lastSelectedTodoID })
        else { return nil }
        return lastSelectedTodoID
    }

    private func openCount(in todos: [Todo]) -> Int {
        todos.filter { !$0.isDone }.count
    }

    private var isTodayPane: Bool {
        if case .today = current { return true }
        return false
    }

    private var isCompletedPane: Bool {
        if case .completed = current { return true }
        return false
    }

    private var showsListBadge: Bool {
        switch current {
        case .list, .noList: return false
        default: return true
        }
    }

    private var paneTitle: String {
        switch current {
        case .today: return "Today"
        case .all: return "All Todos"
        case .completed: return "Completed"
        case .noList: return "No List"
        case .list(let id): return lists.first { $0.persistentModelID == id }?.name ?? "List"
        }
    }

    private var paneSubtitle: String {
        switch current {
        case .today:
            let f = DateFormatter()
            f.dateStyle = .full
            f.timeStyle = .none
            return f.string(from: today)
        case .all:
            return "Everything, across all lists"
        case .completed:
            return "\(completedTodos.count) done, across all lists"
        case .noList:
            return "Todos that aren’t filed into a list"
        case .list:
            return "\(visibleTodos.filter { !$0.isDone }.count) open"
        }
    }

    // MARK: Actions

    private func seedIfNeeded() {
        guard lists.isEmpty else { return }
        context.insert(TodoList(name: "Work", colorName: "purple", sortIndex: 0))
        context.insert(TodoList(name: "Private", colorName: "green", sortIndex: 1))
    }

    private func addTodo(titled title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let todo = Todo(title: trimmed)
        context.insert(todo)

        // Anything added outside a concrete list stays unfiled, so it shows up under “No List”.
        if case .list(let id) = current {
            todo.list = lists.first { $0.persistentModelID == id }
        }
        if isTodayPane { todo.addToDailyPlan(on: today) }

        withAnimation(Motion.reveal) { selectedTodoID = todo.persistentModelID }
    }

    private func addList() {
        let list = TodoList(name: "New List",
                            colorName: ListPalette.names[lists.count % ListPalette.names.count],
                            sortIndex: (lists.map(\.sortIndex).max() ?? 0) + 1)
        withAnimation(Motion.list) {
            context.insert(list)
            route = .list(list.persistentModelID)
        }
        renameText = list.name
        renamingList = list
    }

    private func delete(_ todo: Todo) {
        withAnimation(Motion.list) {
            if selectedTodoID == todo.persistentModelID { selectedTodoID = nil }
            context.delete(todo)
        }
    }
}

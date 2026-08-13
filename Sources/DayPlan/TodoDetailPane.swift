import SwiftUI
import SwiftData

struct TodoDetailPane: View {
    let todo: Todo?
    let lists: [TodoList]
    let today: Date
    let includeOverdue: Bool
    let onClose: () -> Void
    let onDelete: (Todo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                // Nothing selected only happens while the pane is collapsing, and
                // an empty state would flash on its way out.
                if let todo {
                    TodoEditor(
                        todo: todo,
                        lists: lists,
                        today: today,
                        includeOverdue: includeOverdue,
                        onDelete: onDelete
                    )
                    .id(todo.persistentModelID)
                    // Selecting another todo slides the new editor in from the right.
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.reveal, value: todo?.persistentModelID)
        }
    }

    private var header: some View {
        HStack {
            Text("Details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .hoverLift(1.18)
            .help("Hide Details (⌥⌘I)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

struct TodoEditor: View {
    @Bindable var todo: Todo
    let lists: [TodoList]
    let today: Date
    let includeOverdue: Bool
    let onDelete: (Todo) -> Void

    private var inDaily: Bool { todo.isInDailyPlan(on: today, includeOverdue: includeOverdue) }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { todo.dueDate ?? today },
            set: { todo.setDueDate($0) }
        )
    }

    private var hasDueBinding: Binding<Bool> {
        Binding(
            get: { todo.dueDate != nil },
            set: { todo.setDueDate($0 ? today : nil) }
        )
    }

    private var listBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { todo.list?.persistentModelID },
            set: { id in todo.list = lists.first { $0.persistentModelID == id } }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $todo.title, axis: .vertical)
                    .font(.headline)
                    .lineLimit(1...3)

                Toggle(isOn: Binding(
                    get: { todo.isDone },
                    set: { newValue in
                        if newValue != todo.isDone {
                            withAnimation(Motion.list) { todo.toggleDone() }
                        }
                    }
                )) {
                    Text("Completed")
                }
            }

            Section("Organize") {
                Picker("List", selection: listBinding) {
                    Text("No List").tag(PersistentIdentifier?.none)
                    ForEach(lists) { list in
                        Label(list.name, systemImage: "circle.fill")
                            .tag(Optional(list.persistentModelID))
                    }
                }

                Picker("Priority", selection: $todo.priority) {
                    ForEach(Priority.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Schedule") {
                Toggle("Due Date", isOn: hasDueBinding)
                if todo.dueDate != nil {
                    DatePicker("Due", selection: dueBinding, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        // Unfolds from the toggle above rather than popping in.
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Toggle(isOn: Binding(
                    get: { inDaily },
                    set: { newValue in
                        if newValue {
                            todo.addToDailyPlan(on: today)
                        } else {
                            todo.removeFromDailyPlan(on: today)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In Today’s Plan")
                        if todo.isAutoDaily(on: today, includeOverdue: includeOverdue) {
                            Text(inDaily ? "Added automatically because it’s due." : "Due today, but you removed it from today.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .animation(Motion.reveal, value: todo.dueDate)
            .animation(Motion.reveal, value: inDaily)

            Section("Notes") {
                TextEditor(text: $todo.notes)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            }

            Section {
                Button("Delete Todo", role: .destructive) { onDelete(todo) }
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI

enum TodoScope: String, CaseIterable, Identifiable {
    case open = "未完成"
    case completed = "已完成"
    case all = "全部"
    var id: String { rawValue }
}

struct TodosView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope: TodoScope = .open
    @State private var searchText = ""
    @State private var showingNewTodo = false
    @State private var editingTodo: TodoItem?
    @State private var pendingDelete: TodoItem?

    private var visibleTodos: [TodoItem] {
        store.todos
            .filter { store.application(id: $0.applicationID)?.isArchived != true }
            .filter { todo in
                scope == .all || (scope == .completed ? todo.isCompleted : !todo.isCompleted)
            }
            .filter { todo in
                guard !searchText.isEmpty else { return true }
                let application = store.application(id: todo.applicationID)
                let company = application.flatMap { store.company(for: $0)?.name } ?? ""
                return todo.title.localizedCaseInsensitiveContains(searchText)
                    || company.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                if $0.priority != $1.priority { return $0.priority.sortValue > $1.priority.sortValue }
                return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("范围", selection: $scope) {
                    ForEach(TodoScope.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 330)
                Spacer()
                Text("\(visibleTodos.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(16)
            Divider()
            if visibleTodos.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: scope == .completed ? "还没有完成记录" : "没有未完成待办", message: "把简历修改、笔试和面试准备记录下来。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleTodos) { todo in
                            TodoCard(todo: todo) {
                                editingTodo = todo
                            } onDelete: {
                                pendingDelete = todo
                            }
                            .transition(
                                .opacity
                                    .combined(with: .scale(scale: 0.97))
                                    .combined(with: .move(edge: .top))
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : AppMotion.standard, value: visibleTodos.map(\.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("待办事项")
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索待办")
        .toolbar {
            Button {
                showingNewTodo = true
            } label: {
                Label("新建待办", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .animation(reduceMotion ? nil : AppMotion.standard, value: scope)
        .animation(reduceMotion ? nil : AppMotion.standard, value: visibleTodos.count)
        .sheet(isPresented: $showingNewTodo) { TodoEditorView() }
        .sheet(item: $editingTodo) { TodoEditorView(todo: $0) }
        .alert("删除待办？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { todo in
            Button("删除", role: .destructive) {
                store.deleteTodo(id: todo.id)
                Task { await ReminderService.refresh(store: store) }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }
}

struct TodoCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(reduceMotion ? nil : AppMotion.standard) {
                    store.toggleTodo(id: todo.id)
                }
                Task { await ReminderService.refresh(store: store) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isCompleted ? .green : todo.priority.color)
            }
            .buttonStyle(ResponsivePlainButtonStyle(pressedScale: 0.9))
            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .font(.headline)
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                HStack(spacing: 10) {
                    if let dueAt = todo.dueAt {
                        Label(AppFormatters.dateTime.string(from: dueAt), systemImage: "calendar")
                            .foregroundStyle(dueAt < Date() && !todo.isCompleted ? .red : .secondary)
                    }
                    if let application = store.application(id: todo.applicationID) {
                        Label("\(store.company(for: application)?.name ?? "未知公司") · \(application.position)", systemImage: "briefcase")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !todo.notes.isEmpty {
                    Text(todo.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            PriorityPill(priority: todo.priority)
            Menu {
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(16)
        .background(
            todo.isCompleted ? Color.green.opacity(0.045) : Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.quaternary) }
        .animation(reduceMotion ? nil : AppMotion.standard, value: todo.isCompleted)
    }
}

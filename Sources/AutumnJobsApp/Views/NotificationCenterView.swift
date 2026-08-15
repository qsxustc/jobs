import SwiftUI

private enum SmartAlertAction {
    case primary
    case completeTodo
    case postponeTodo(days: Int)
    case editTodo
}

struct NotificationCenterView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection?
    @Binding var selectedApplicationID: UUID?
    @State private var editingEvent: ProcessEvent?
    @State private var editingTodo: TodoItem?

    private var alerts: [SmartAlertItem] {
        SmartAlertService.items(store: store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("需要你关注的事项")
                            .font(.title2.bold())
                        Text("根据投递、日程和待办自动生成，完成或更新记录后会自动消失。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(alerts.count) 条")
                        .font(.headline)
                        .foregroundStyle(alerts.isEmpty ? Color.secondary : Color.orange)
                }

                if alerts.isEmpty {
                    EmptyStateView(icon: "bell.and.waves.left.and.right", title: "目前没有提醒", message: "所有流程、日程和待办都处于正常状态。")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(alerts) { alert in
                            SmartAlertCard(alert: alert) { action in
                                performAction(action, for: alert)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("提醒中心")
        .sheet(item: $editingEvent) { event in
            EventEditorView(applicationID: event.applicationID, event: event)
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditorView(todo: todo)
        }
    }

    private func performAction(_ action: SmartAlertAction, for alert: SmartAlertItem) {
        switch action {
        case .completeTodo:
            if let id = alert.todoID {
                store.toggleTodo(id: id)
                Task { await ReminderService.refresh(store: store) }
            }
        case .postponeTodo(let days):
            if let id = alert.todoID {
                store.postponeTodo(id: id, byDays: days)
                Task { await ReminderService.refresh(store: store) }
            }
        case .editTodo:
            editingTodo = store.todos.first { $0.id == alert.todoID }
        case .primary:
            performPrimaryAction(alert)
        }
    }

    private func performPrimaryAction(_ alert: SmartAlertItem) {
        switch alert.kind {
        case .overdueTodo:
            break
        case .staleApplication, .projectDeadline:
            guard let id = alert.applicationID, store.application(id: id) != nil else { return }
            selectedApplicationID = id
            selection = .applications
        case .upcomingEvent, .missingReview:
            editingEvent = store.events.first { $0.id == alert.eventID }
        }
    }
}

private struct SmartAlertCard: View {
    @EnvironmentObject private var store: AppStore
    let alert: SmartAlertItem
    let action: (SmartAlertAction) -> Void

    private var color: Color {
        switch alert.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var icon: String {
        switch alert.kind {
        case .overdueTodo: return "exclamationmark.circle.fill"
        case .upcomingEvent: return "calendar.badge.clock"
        case .staleApplication: return "arrow.clockwise.circle.fill"
        case .missingReview: return "square.and.pencil"
        case .projectDeadline: return "hourglass.bottomhalf.filled"
        }
    }

    private var actionTitle: String? {
        switch alert.kind {
        case .overdueTodo: return nil
        case .upcomingEvent: return "查看日程"
        case .staleApplication: return "去处理"
        case .missingReview: return "补充复盘"
        case .projectDeadline: return "查看投递"
        }
    }

    private var projectURL: URL? {
        guard let projectID = alert.projectID,
              let value = store.projects.first(where: { $0.id == projectID })?.url,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                Text(alert.title).font(.headline)
                Text(alert.message).foregroundStyle(.secondary)
                if let date = alert.date {
                    Text(AppFormatters.fullDate.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            actions
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.22)) }
    }

    @ViewBuilder
    private var actions: some View {
        if alert.kind == .overdueTodo {
            HStack(spacing: 7) {
                Button("完成") { action(.completeTodo) }
                    .buttonStyle(.borderedProminent)
                Menu("延期") {
                    Button("延期 1 天") { action(.postponeTodo(days: 1)) }
                    Button("延期 3 天") { action(.postponeTodo(days: 3)) }
                    Button("延期 1 周") { action(.postponeTodo(days: 7)) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("编辑") { action(.editTodo) }
                    .buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 7) {
                if let actionTitle {
                    Button(actionTitle) { action(.primary) }
                        .buttonStyle(.bordered)
                }
                if let projectURL {
                    Link("打开招聘页", destination: projectURL)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

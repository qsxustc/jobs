import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingEvent: ProcessEvent?

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
                            SmartAlertCard(alert: alert) {
                                performAction(alert)
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
    }

    private func performAction(_ alert: SmartAlertItem) {
        switch alert.kind {
        case .overdueTodo:
            if let id = alert.todoID {
                store.toggleTodo(id: id)
                Task { await ReminderService.refresh(store: store) }
            }
        case .staleApplication:
            if let id = alert.applicationID { store.touchApplication(id: id) }
        case .upcomingEvent, .missingReview:
            editingEvent = store.events.first { $0.id == alert.eventID }
        case .projectDeadline:
            break
        }
    }
}

private struct SmartAlertCard: View {
    let alert: SmartAlertItem
    let action: () -> Void

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
        case .overdueTodo: return "标记完成"
        case .upcomingEvent: return "查看日程"
        case .staleApplication: return "标记已跟进"
        case .missingReview: return "补充复盘"
        case .projectDeadline: return nil
        }
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
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.22)) }
    }
}

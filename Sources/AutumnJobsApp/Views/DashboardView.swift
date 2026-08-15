import SwiftUI
import Charts

private struct DashboardStageCount: Identifiable {
    let id: String
    let name: String
    let count: Int
    let color: Color
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection?
    @State private var editingApplication: JobApplication?
    @State private var showingNewTodo = false

    private var interviewingCount: Int {
        store.applicationCount(in: .interview)
    }

    private var offerCount: Int {
        store.applicationCount(in: .offer)
    }

    private var nextSevenDays: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private var sevenDayEvents: [ProcessEvent] {
        store.upcomingEvents.filter { $0.startsAt <= nextSevenDays }
    }

    private var nearbyEvents: [ProcessEvent] {
        Array(sevenDayEvents.prefix(5))
    }

    private var staleApplications: [JobApplication] {
        let threshold = Calendar.current.date(byAdding: .day, value: -store.settings.staleDays, to: Date()) ?? Date()
        return store.activeApplications
            .filter { store.isActive($0) && $0.updatedAt < threshold }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                metrics
                HStack(alignment: .top, spacing: 18) {
                    scheduleCard
                    todosCard
                }
                HStack(alignment: .top, spacing: 18) {
                    funnelCard
                    staleCard
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("概览")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingNewTodo = true
                } label: {
                    Label("新建待办", systemImage: "checkmark.circle.badge.plus")
                }
                Button {
                    NotificationCenter.default.post(name: .newApplication, object: nil)
                } label: {
                    Label("新建投递", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: $editingApplication) { application in
            ApplicationEditorView(application: application)
        }
        .sheet(isPresented: $showingNewTodo) {
            TodoEditorView()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.largeTitle.bold())
                Text("把每一次投递都变成看得见的进展。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    selection = .notifications
                } label: {
                    Label("\(SmartAlertService.items(store: store).count)", systemImage: "bell.badge")
                }
                .buttonStyle(.bordered)
                .help("查看智能提醒")
                Text(Date(), format: .dateTime.year().month().day().weekday(.wide))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            MetricCard(title: "全部投递", value: "\(store.activeApplications.count)", subtitle: "持续积累机会池", icon: "paperplane.fill", color: .blue)
            MetricCard(title: "面试中", value: "\(interviewingCount)", subtitle: "正在推进的流程", icon: "person.2.fill", color: .purple)
            MetricCard(title: "Offer", value: "\(offerCount)", subtitle: offerCount == 0 ? "好消息正在路上" : "继续保持", icon: "trophy.fill", color: .green)
            MetricCard(title: "未来日程", value: "\(sevenDayEvents.count)", subtitle: "未来 7 天", icon: "calendar.badge.clock", color: .orange)
        }
    }

    private var scheduleCard: some View {
        SectionCard("近期日程", subtitle: "未来七天的笔试、面试和沟通") {
            if nearbyEvents.isEmpty {
                EmptyStateView(icon: "calendar", title: "近期没有安排", message: "在投递详情中添加面试或笔试。")
            } else {
                VStack(spacing: 0) {
                    ForEach(nearbyEvents) { event in
                        EventCompactRow(event: event)
                        if event.id != nearbyEvents.last?.id { Divider() }
                    }
                }
                Button("查看全部日程") { selection = .schedule }
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var todosCard: some View {
        SectionCard("待办事项", subtitle: "先完成最重要的准备") {
            if store.openTodos.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "待办已清空", message: "今天的准备工作都完成了。")
            } else {
                VStack(spacing: 4) {
                    ForEach(store.openTodos.prefix(5)) { todo in
                        TodoCompactRow(todo: todo)
                    }
                }
                Button("查看全部待办") { selection = .todos }
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var funnelCard: some View {
        let values = ApplicationAnalysisCategory.allCases.compactMap { category -> DashboardStageCount? in
            let count = store.applicationCount(in: category)
            return count > 0 ? DashboardStageCount(
                id: category.id,
                name: category.rawValue,
                count: count,
                color: category.color
            ) : nil
        }
        return SectionCard("当前流程分布", subtitle: "按统一分析分类统计当前机会") {
            if values.isEmpty {
                EmptyStateView(icon: "chart.bar", title: "暂无数据", message: "新增投递后会自动生成分布。")
            } else {
                Chart(values) { item in
                    BarMark(
                        x: .value("数量", item.count),
                        y: .value("状态", item.name)
                    )
                    .foregroundStyle(item.color.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var staleCard: some View {
        SectionCard("需要跟进", subtitle: "超过 \(store.settings.staleDays) 天没有更新的流程") {
            if staleApplications.isEmpty {
                EmptyStateView(icon: "sparkles", title: "没有积压", message: "所有进行中的流程都在近期更新过。")
            } else {
                VStack(spacing: 0) {
                    ForEach(staleApplications.prefix(5)) { application in
                        Button {
                            editingApplication = application
                        } label: {
                            HStack(spacing: 10) {
                                CompanyAvatar(name: store.company(for: application)?.name ?? "?", size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.company(for: application)?.name ?? "未知公司")
                                        .fontWeight(.medium)
                                    Text(application.position)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(AppFormatters.relative.localizedString(for: application.updatedAt, relativeTo: Date()))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 { return "夜深了，注意休息" }
        if hour < 12 { return "早上好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }
}

struct EventCompactRow: View {
    @EnvironmentObject private var store: AppStore
    let event: ProcessEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(event.startsAt, format: .dateTime.day())
                    .font(.title3.bold())
                Text(event.startsAt, format: .dateTime.month(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 46)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).fontWeight(.semibold)
                if let application = store.application(id: event.applicationID) {
                    Text("\(store.company(for: application)?.name ?? "未知公司") · \(application.position)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(event.startsAt, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
    }
}

struct TodoCompactRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let todo: TodoItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : AppMotion.standard) {
                    store.toggleTodo(id: todo.id)
                }
                Task { await ReminderService.refresh(store: store) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(ResponsivePlainButtonStyle(pressedScale: 0.9))
            .foregroundStyle(todo.isCompleted ? .green : todo.priority.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .lineLimit(1)
                if let dueAt = todo.dueAt {
                    Text(AppFormatters.dateTime.string(from: dueAt))
                        .font(.caption)
                        .foregroundStyle(dueAt < Date() && !todo.isCompleted ? .red : .secondary)
                }
            }
            Spacer()
            PriorityPill(priority: todo.priority)
        }
        .padding(.vertical, 5)
    }
}

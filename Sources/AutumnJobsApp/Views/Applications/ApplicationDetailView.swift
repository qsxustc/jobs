import SwiftUI

struct ApplicationDetailView: View {
    @EnvironmentObject private var store: AppStore
    let application: JobApplication
    @State private var showingEditor = false
    @State private var showingEventEditor = false
    @State private var editingEvent: ProcessEvent?
    @State private var showingTodoEditor = false
    @State private var editingTodo: TodoItem?
    @State private var eventToDelete: ProcessEvent?

    private var company: Company? { store.company(for: application) }
    private var project: RecruitmentProject? { store.project(for: application) }
    private var applicationEvents: [ProcessEvent] { store.events(for: application.id) }
    private var applicationTodos: [TodoItem] { store.todos(for: application.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickInfo
                eventsSection
                notesSection
                todosSection
                jdSection
                historySection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingEditor) {
            ApplicationEditorView(application: application)
        }
        .sheet(isPresented: $showingEventEditor) {
            EventEditorView(applicationID: application.id)
        }
        .sheet(item: $editingEvent) { event in
            EventEditorView(applicationID: application.id, event: event)
        }
        .sheet(isPresented: $showingTodoEditor) {
            TodoEditorView(applicationID: application.id)
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditorView(applicationID: application.id, todo: todo)
        }
        .alert("删除这条流程记录？", isPresented: Binding(
            get: { eventToDelete != nil },
            set: { if !$0 { eventToDelete = nil } }
        ), presenting: eventToDelete) { event in
            Button("删除", role: .destructive) {
                store.deleteEvent(id: event.id)
                Task { await ReminderService.refresh(store: store) }
            }
            Button("取消", role: .cancel) { eventToDelete = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            CompanyAvatar(name: company?.name ?? "?", size: 60)
            VStack(alignment: .leading, spacing: 7) {
                Text(company?.name ?? "未知公司")
                    .font(.title.bold())
                Text(application.position)
                    .font(.title3)
                HStack(spacing: 8) {
                    Menu {
                        Section("标准状态") {
                            ForEach(ApplicationStatus.allCases) { status in
                                Button {
                                    store.updateStatus(applicationID: application.id, to: status)
                                } label: {
                                    if status == application.status && application.customStageID == nil {
                                        Label(status.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(status.rawValue)
                                    }
                                }
                            }
                        }
                        if !store.customStages.isEmpty {
                            Section("自定义状态") {
                                ForEach(store.customStages.sorted { $0.order < $1.order }) { stage in
                                    Button {
                                        store.updateCustomStage(applicationID: application.id, customStageID: stage.id)
                                    } label: {
                                        if application.customStageID == stage.id {
                                            Label(stage.name, systemImage: "checkmark")
                                        } else {
                                            Text(stage.name)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        EffectiveStatusPill(application: application)
                    }
                    .menuStyle(.borderlessButton)
                    PriorityPill(priority: application.priority)
                    if store.interviewCount(for: application.id) > 0 {
                        Text("已记录 \(store.interviewCount(for: application.id)) 轮面试")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button("编辑") { showingEditor = true }
                .buttonStyle(.bordered)
        }
    }

    private var quickInfo: some View {
        SectionCard("岗位信息") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                infoItem("招聘项目", project?.name ?? "未关联")
                infoItem("工作地点", application.location.isEmpty ? "未填写" : application.location)
                infoItem("岗位类别", application.category.isEmpty ? "未填写" : application.category)
                infoItem("投递渠道", application.channel.isEmpty ? "未填写" : application.channel)
                infoItem("简历版本", store.resumeVersion(for: application)?.name ?? "未指定")
                infoItem("投递时间", application.appliedAt.map { AppFormatters.fullDate.string(from: $0) } ?? "尚未投递")
                infoItem("岗位薪资范围", application.salary.isEmpty ? "未填写" : application.salary)
                infoItem(
                    "Offer 薪资",
                    application.offerSalary.isEmpty ? "未填写" : application.offerSalary,
                    emphasized: !application.offerSalary.isEmpty
                )
                infoItem("最近更新", AppFormatters.fullDate.string(from: application.updatedAt))
            }
            let applicationTags = store.tags(for: application)
            if !applicationTags.isEmpty {
                HStack(spacing: 6) {
                    Text("标签").font(.caption).foregroundStyle(.secondary)
                    ForEach(applicationTags) { tag in TagPill(tag: tag) }
                }
            }
            HStack(spacing: 14) {
                urlButton("打开职位链接", value: application.jdURL, icon: "link")
                urlButton("招聘项目", value: project?.url ?? "", icon: "briefcase")
                urlButton("公司官网", value: company?.website ?? "", icon: "globe")
            }
        }
    }

    private var eventsSection: some View {
        SectionCard("流程与面试", subtitle: "笔试、面试和 Offer 沟通都记录在同一时间线") {
            HStack {
                if let next = store.nextEvent(for: application.id) {
                    Label("下一项：\(next.title) · \(AppFormatters.dateTime.string(from: next.startsAt))", systemImage: "clock.badge")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                } else {
                    Text("暂无待进行的流程")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingEventEditor = true
                } label: {
                    Label("添加流程", systemImage: "plus")
                }
            }
            Divider()
            if applicationEvents.isEmpty {
                EmptyStateView(icon: "person.crop.rectangle.stack", title: "尚未记录流程", message: "添加测评、笔试或面试安排。")
            } else {
                VStack(spacing: 0) {
                    ForEach(applicationEvents) { event in
                        ProcessEventRow(event: event) {
                            editingEvent = event
                        } onDelete: {
                            eventToDelete = event
                        }
                        if event.id != applicationEvents.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var todosSection: some View {
        SectionCard("关联待办") {
            HStack {
                Text("围绕这个岗位的准备清单")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingTodoEditor = true
                } label: {
                    Label("添加待办", systemImage: "plus")
                }
            }
            if applicationTodos.isEmpty {
                EmptyStateView(icon: "checklist", title: "没有关联待办", message: "把简历修改、面试准备等工作拆成待办。")
            } else {
                ForEach(applicationTodos) { todo in
                    HStack {
                        TodoCompactRow(todo: todo)
                        Button {
                            editingTodo = todo
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        SectionCard("备注") {
            if application.notes.isEmpty {
                Text("暂无备注")
                    .foregroundStyle(.secondary)
            } else {
                Text(application.notes)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var jdSection: some View {
        let jdText = application.jdText ?? ""
        let requirements = application.requirements ?? ""
        if !jdText.isEmpty || !requirements.isEmpty {
            SectionCard("JD 与岗位要求") {
                if !requirements.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("岗位要求").font(.caption).foregroundStyle(.secondary)
                        Text(requirements)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !jdText.isEmpty {
                    DisclosureGroup("查看 JD 原文") {
                        Text(jdText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        SectionCard("状态历史") {
            let history = store.history(for: application.id)
            if history.isEmpty {
                Text("暂无状态变更记录").foregroundStyle(.secondary)
            } else {
                ForEach(history) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Circle()
                            .fill(item.toStatus.color)
                            .frame(width: 8, height: 8)
                        Text((item.fromCustomName ?? item.fromStatus?.rawValue).map { "\($0) → " } ?? "创建于 ")
                        + Text(item.toCustomName ?? item.toStatus.rawValue).fontWeight(.semibold)
                        Spacer()
                        Text(AppFormatters.fullDate.string(from: item.changedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func infoItem(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? Color.green : Color.primary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func urlButton(_ label: String, value: String, icon: String) -> some View {
        if let url = URL(string: value), !value.isEmpty {
            Link(destination: url) {
                Label(label, systemImage: icon)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ProcessEventRow: View {
    let event: ProcessEvent
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: event.type.isInterview ? "person.wave.2.fill" : "doc.text.fill")
                .foregroundStyle(event.result == .passed ? .green : .blue)
                .frame(width: 34, height: 34)
                .background((event.result == .passed ? Color.green : Color.blue).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.title).fontWeight(.semibold)
                    Text(event.result.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(event.result == .failed ? .red : .secondary)
                }
                Text("\(AppFormatters.dateTime.string(from: event.startsAt)) · \(event.format.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !event.review.isEmpty {
                    Text(event.review)
                        .font(.caption)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Menu {
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 10)
    }
}

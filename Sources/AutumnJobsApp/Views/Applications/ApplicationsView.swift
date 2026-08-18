import SwiftUI

private enum ApplicationStageFilter: Hashable {
    case all
    case builtIn(ApplicationStatus)
    case custom(UUID)
}

struct ApplicationsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedID: UUID?
    @State private var searchText = ""
    @State private var stageFilter: ApplicationStageFilter = .all
    @State private var tagFilter: UUID?
    @State private var includeArchived = false
    @State private var showingNewApplication = false
    @State private var pendingDelete: JobApplication?

    private var filteredApplications: [JobApplication] {
        store.applications
            .filter { includeArchived || !$0.isArchived }
            .filter { application in
                switch stageFilter {
                case .all: return true
                case .builtIn(let status): return application.customStageID == nil && application.status == status
                case .custom(let id): return application.customStageID == id
                }
            }
            .filter { application in
                guard let tagFilter else { return true }
                return application.tagIDs?.contains(tagFilter) == true
            }
            .filter { application in
                guard !searchText.isEmpty else { return true }
                let companyName = store.company(for: application)?.name ?? ""
                let projectName = store.project(for: application)?.name ?? ""
                return [companyName, projectName, application.position, application.location, application.category]
                    .contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .sorted {
                if $0.priority != $1.priority { return $0.priority.sortValue > $1.priority.sortValue }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filterBar
                Divider()
                if filteredApplications.isEmpty {
                    EmptyStateView(icon: "tray", title: "没有匹配的投递", message: "调整筛选条件，或新建第一条投递记录。")
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    List(filteredApplications, selection: $selectedID) { application in
                        ApplicationListRow(application: application)
                            .tag(application.id)
                            .contextMenu {
                                Button(application.isArchived ? "取消归档" : "归档") {
                                    store.archiveApplication(id: application.id)
                                    if store.lastSaveError == nil {
                                        Task { await ReminderService.refresh(store: store) }
                                    }
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    pendingDelete = application
                                }
                            }
                    }
                    .listStyle(.inset)
                    .animation(reduceMotion ? nil : AppMotion.standard, value: filteredApplications.map(\.id))
                }
            }
            .frame(width: 410)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            ZStack {
                if let selectedID, let application = store.application(id: selectedID) {
                    ApplicationDetailView(application: application)
                        .id(application.id)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .opacity.combined(with: .offset(x: 6))
                        )
                } else {
                    ContentUnavailableView(
                        "选择一条投递记录",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("在左侧选择岗位，查看流程、面试和待办详情。")
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(reduceMotion ? nil : AppMotion.standard, value: selectedID)
        }
        .navigationTitle("投递记录")
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索公司、项目或岗位")
        .toolbar {
            Button {
                showingNewApplication = true
            } label: {
                Label("新建投递", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showingNewApplication) {
            ApplicationEditorView()
        }
        .alert("删除投递记录？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { application in
            Button("删除", role: .destructive) {
                store.deleteApplication(id: application.id)
                Task { await ReminderService.refresh(store: store) }
                if selectedID == application.id { selectedID = nil }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("相关面试、待办和状态历史也会被删除，此操作无法撤销。")
        }
        .onAppear {
            syncSelection(with: filteredApplications.map(\.id))
        }
        .onChange(of: filteredApplications.map(\.id)) { _, visibleIDs in
            syncSelection(with: visibleIDs)
        }
    }

    private func syncSelection(with visibleIDs: [UUID]) {
        if let selectedID, visibleIDs.contains(selectedID) { return }
        withAnimation(reduceMotion ? nil : AppMotion.standard) {
            selectedID = visibleIDs.first
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("状态", selection: $stageFilter) {
                Text("全部状态").tag(ApplicationStageFilter.all)
                Divider()
                ForEach(ApplicationStatus.allCases) { status in
                    Text(status.rawValue).tag(ApplicationStageFilter.builtIn(status))
                }
                if !store.customStages.isEmpty {
                    Divider()
                    ForEach(store.customStages.sorted { $0.order < $1.order }) { stage in
                        Text(stage.name).tag(ApplicationStageFilter.custom(stage.id))
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 150)

            if !store.tags.isEmpty {
                Picker("标签", selection: $tagFilter) {
                    Text("全部标签").tag(nil as UUID?)
                    ForEach(store.tags) { tag in
                        Text(tag.name).tag(tag.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }

            Toggle("含归档", isOn: $includeArchived)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            Text("\(filteredApplications.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : AppMotion.standard, value: filteredApplications.count)
        }
        .padding(10)
    }
}

struct ApplicationListRow: View {
    @EnvironmentObject private var store: AppStore
    let application: JobApplication

    var body: some View {
        HStack(spacing: 12) {
            CompanyAvatar(name: store.company(for: application)?.name ?? "?", size: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(store.company(for: application)?.name ?? "未知公司")
                        .fontWeight(.semibold)
                    if application.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(application.position)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    EffectiveStatusPill(application: application)
                    if !application.location.isEmpty {
                        Label(application.location, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                let applicationTags = store.tags(for: application)
                if !applicationTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(applicationTags.prefix(2)) { tag in TagPill(tag: tag) }
                        if applicationTags.count > 2 {
                            Text("+\(applicationTags.count - 2)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                PriorityPill(priority: application.priority)
                Text(AppFormatters.relative.localizedString(for: application.updatedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

import SwiftUI

struct KanbanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var editingApplication: JobApplication?
    @State private var showingNewApplication = false

    private func applications(for status: ApplicationStatus) -> [JobApplication] {
        store.activeApplications
            .filter { $0.customStageID == nil && $0.status == status }
            .filter { application in
                guard !searchText.isEmpty else { return true }
                return (store.company(for: application)?.name ?? "").localizedCaseInsensitiveContains(searchText)
                    || application.position.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.priority != $1.priority { return $0.priority.sortValue > $1.priority.sortValue }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(ApplicationStatus.allCases) { status in
                    KanbanColumn(status: status, applications: applications(for: status)) { application in
                        editingApplication = application
                    }
                }
                ForEach(store.customStages.sorted { $0.order < $1.order }) { stage in
                    let stageApplications = store.activeApplications
                        .filter { $0.customStageID == stage.id }
                        .filter { application in
                            searchText.isEmpty
                            || (store.company(for: application)?.name ?? "").localizedCaseInsensitiveContains(searchText)
                            || application.position.localizedCaseInsensitiveContains(searchText)
                        }
                        .sorted { $0.updatedAt > $1.updatedAt }
                    CustomKanbanColumn(stage: stage, applications: stageApplications) { application in
                        editingApplication = application
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("流程看板")
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索公司或岗位")
        .toolbar {
            Button {
                showingNewApplication = true
            } label: {
                Label("新建投递", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(item: $editingApplication) { application in
            ApplicationEditorView(application: application)
        }
        .sheet(isPresented: $showingNewApplication) {
            ApplicationEditorView()
        }
    }
}

struct KanbanColumn: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: ApplicationStatus
    let applications: [JobApplication]
    let onOpen: (JobApplication) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(status.color).frame(width: 9, height: 9)
                Text(status.rawValue).font(.headline)
                Spacer()
                Text("\(applications.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .contentTransition(.numericText())
            }
            if applications.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "tray").font(.title2)
                    Text("拖到这里更新状态").font(.caption)
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(applications) { application in
                    KanbanCard(application: application, onOpen: { onOpen(application) })
                        .draggable(application.id.uuidString)
                        .transition(
                            .opacity
                                .combined(with: .scale(scale: 0.96))
                                .combined(with: .move(edge: .top))
                        )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 270)
        .frame(minHeight: 580, alignment: .top)
        .background(
            isTargeted ? status.color.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isTargeted ? status.color : .clear, lineWidth: 2)
        }
        .animation(reduceMotion ? nil : AppMotion.quick, value: isTargeted)
        .animation(reduceMotion ? nil : AppMotion.emphasized, value: applications.map(\.id))
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first, let id = UUID(uuidString: rawID) else { return false }
            withAnimation(reduceMotion ? nil : AppMotion.emphasized) {
                store.updateStatus(applicationID: id, to: status)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

struct KanbanCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let application: JobApplication
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    CompanyAvatar(name: store.company(for: application)?.name ?? "?", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.company(for: application)?.name ?? "未知公司")
                            .fontWeight(.semibold)
                        Text(application.position)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(application.priority.color)
                }
                if let next = store.nextEvent(for: application.id) {
                    Label("\(next.title) · \(AppFormatters.dateTime.string(from: next.startsAt))", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                } else if let appliedAt = application.appliedAt {
                    Label("投递于 \(AppFormatters.date.string(from: appliedAt))", systemImage: "paperplane")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !application.location.isEmpty || !application.category.isEmpty {
                    Text([application.location, application.category].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(.quaternary) }
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsivePlainButtonStyle())
        .interactiveCard()
        .contextMenu {
            Menu("移动到") {
                ForEach(ApplicationStatus.allCases) { status in
                    Button(status.rawValue) {
                        withAnimation(reduceMotion ? nil : AppMotion.emphasized) {
                            store.updateStatus(applicationID: application.id, to: status)
                        }
                    }
                }
                if !store.customStages.isEmpty {
                    Divider()
                    ForEach(store.customStages.sorted { $0.order < $1.order }) { stage in
                        Button(stage.name) {
                            withAnimation(reduceMotion ? nil : AppMotion.emphasized) {
                                store.updateCustomStage(applicationID: application.id, customStageID: stage.id)
                            }
                        }
                    }
                }
            }
            Button("编辑", action: onOpen)
        }
    }
}

struct CustomKanbanColumn: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: CustomStage
    let applications: [JobApplication]
    let onOpen: (JobApplication) -> Void
    @State private var isTargeted = false

    var body: some View {
        let color = Color.jobColor(stage.colorKey)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(stage.name).font(.headline)
                Spacer()
                Text("\(applications.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .contentTransition(.numericText())
            }
            if applications.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "tray").font(.title2)
                    Text("拖到这里更新状态").font(.caption)
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(applications) { application in
                    KanbanCard(application: application, onOpen: { onOpen(application) })
                        .draggable(application.id.uuidString)
                        .transition(
                            .opacity
                                .combined(with: .scale(scale: 0.96))
                                .combined(with: .move(edge: .top))
                        )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 270)
        .frame(minHeight: 580, alignment: .top)
        .background(
            isTargeted ? color.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isTargeted ? color : .clear, lineWidth: 2)
        }
        .animation(reduceMotion ? nil : AppMotion.quick, value: isTargeted)
        .animation(reduceMotion ? nil : AppMotion.emphasized, value: applications.map(\.id))
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first, let id = UUID(uuidString: rawID) else { return false }
            withAnimation(reduceMotion ? nil : AppMotion.emphasized) {
                store.updateCustomStage(applicationID: id, customStageID: stage.id)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

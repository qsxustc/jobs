import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "概览"
    case applications = "投递记录"
    case board = "流程看板"
    case schedule = "日程与面试"
    case todos = "待办事项"
    case notifications = "提醒中心"
    case resumes = "简历版本"
    case analytics = "数据分析"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .applications: return "tray.full"
        case .board: return "rectangle.3.group"
        case .schedule: return "calendar"
        case .todos: return "checklist"
        case .notifications: return "bell.badge"
        case .resumes: return "doc.text"
        case .analytics: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppSection? = .dashboard
    @State private var selectedApplicationID: UUID?
    @State private var showingNewApplication = false

    private var alertCount: Int {
        SmartAlertService.items(store: store).count
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(AppSection.allCases) { section in
                            Button {
                                withAnimation(reduceMotion ? nil : AppMotion.standard) {
                                    selection = section
                                }
                            } label: {
                                SidebarRow(
                                    section: section,
                                    isSelected: selection == section,
                                    alertCount: section == .notifications ? alertCount : 0
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityValue(selection == section ? "已选择" : "")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }

                sidebarSummary
            }
            .navigationTitle("秋招助手")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            ZStack {
                detailView
                    .id(selection ?? .dashboard)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .offset(x: 7))
                    )
            }
            .animation(reduceMotion ? nil : AppMotion.standard, value: selection)
        }
        .sheet(isPresented: $showingNewApplication) {
            ApplicationEditorView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newApplication)) { _ in
            showingNewApplication = true
        }
        .alert("数据保存异常", isPresented: Binding(
            get: { store.lastSaveError != nil },
            set: { if !$0 { store.lastSaveError = nil } }
        )) {
            Button("好") { store.lastSaveError = nil }
        } message: {
            Text(store.lastSaveError ?? "")
        }
        .alert("通知调度异常", isPresented: Binding(
            get: { store.lastNotificationError != nil },
            set: { if !$0 { store.lastNotificationError = nil } }
        )) {
            Button("好") { store.lastNotificationError = nil }
        } message: {
            Text(store.lastNotificationError ?? "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .dashboard {
        case .dashboard: DashboardView(selection: $selection)
        case .applications: ApplicationsView(selectedID: $selectedApplicationID)
        case .board: KanbanView()
        case .schedule: ScheduleView()
        case .todos: TodosView()
        case .notifications: NotificationCenterView(
            selection: $selection,
            selectedApplicationID: $selectedApplicationID
        )
        case .resumes: ResumeVersionsView()
        case .analytics: AnalyticsView()
        case .settings: SettingsView()
        }
    }

    private var sidebarSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Label("进行中", systemImage: "bolt.fill")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.activeApplications.filter { store.isActive($0) }.count)")
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
            }
            HStack {
                Label("未完成待办", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.openTodos.count)")
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : AppMotion.standard, value: store.activeApplications.count)
        .animation(reduceMotion ? nil : AppMotion.standard, value: store.openTodos.count)
    }
}

private struct SidebarRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let section: AppSection
    let isSelected: Bool
    let alertCount: Int
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            Text(section.rawValue)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if alertCount > 0 {
                Text("\(alertCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : AppMotion.standard, value: alertCount)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : AppMotion.quick, value: isHovered)
        .animation(reduceMotion ? nil : AppMotion.standard, value: isSelected)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.13) }
        if isHovered { return Color.primary.opacity(0.055) }
        return .clear
    }
}

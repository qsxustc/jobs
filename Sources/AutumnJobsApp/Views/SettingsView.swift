import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum SettingsDeleteTarget: Identifiable {
    case stage(CustomStage)
    case tag(JobTag)

    var id: String {
        switch self {
        case .stage(let stage): return "stage-\(stage.id)"
        case .tag(let tag): return "tag-\(tag.id)"
        }
    }
}

private enum ImportFileError: LocalizedError {
    case tooLarge(label: String, megabytes: Int)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let label, let megabytes):
            return "\(label)文件过大，最大支持 \(megabytes) MB。"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var localSettings = UserSettings()
    @State private var resultMessage: String?
    @State private var isRequestingNotifications = false
    @State private var newStageName = ""
    @State private var newStageColor = "indigo"
    @State private var newStageIsTerminal = false
    @State private var newStageAnalysisCategory: ApplicationAnalysisCategory = .submitted
    @State private var newTagName = ""
    @State private var newTagColor = "blue"
    @State private var deleteTarget: SettingsDeleteTarget?
    @State private var pendingBackupURL: URL?

    private let colorOptions = ["red", "orange", "yellow", "green", "teal", "blue", "indigo", "purple", "pink", "gray"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCard("提醒设置", subtitle: "面试和待办提醒由 macOS 通知中心发送") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(localSettings.notificationsEnabled ? "系统通知已开启" : "系统通知未开启", systemImage: localSettings.notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                                .font(.headline)
                            Text("默认在面试前 1 天和 2 小时提醒，具体时间可在每条日程中修改。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if localSettings.notificationsEnabled {
                            Button("关闭通知") {
                                localSettings.notificationsEnabled = false
                                saveSettings()
                            }
                        } else {
                            Button("开启通知") {
                                requestNotifications()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRequestingNotifications)
                        }
                    }
                    Divider()
                    Stepper("流程超过 \(localSettings.staleDays) 天未更新时提示跟进", value: $localSettings.staleDays, in: 1...365)
                    Picker("新建待办的默认提醒", selection: $localSettings.defaultReminderMinutes) {
                        Text("不提醒").tag(0)
                        Text("提前 15 分钟").tag(15)
                        Text("提前 2 小时").tag(120)
                        Text("提前 1 天").tag(1_440)
                        if ![0, 15, 120, 1_440].contains(localSettings.defaultReminderMinutes) {
                            Divider()
                            Text("提前 \(AppFormatters.reminderLeadTime(localSettings.defaultReminderMinutes))（自定义）")
                                .tag(localSettings.defaultReminderMinutes)
                        }
                    }
                    Button("保存提醒偏好") { saveSettings() }
                }

                SectionCard("后台节能", subtitle: "关闭所有窗口一段时间后释放应用占用的内存") {
                    Picker("自动退出", selection: $localSettings.backgroundIdleMinutes) {
                        Text("不自动退出").tag(0)
                        Text("5 分钟后").tag(5)
                        Text("15 分钟后").tag(15)
                        Text("30 分钟后").tag(30)
                        Text("1 小时后").tag(60)
                    }
                    .pickerStyle(.segmented)
                    Text("窗口仍打开但应用处于后台时，由 macOS App Nap 自动休眠；关闭全部窗口后自动退出可进一步释放内存，已安排的系统通知不受影响。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("保存后台节能设置") { saveSettings(refreshReminders: false) }
                }

                SectionCard("数据导入与导出", subtitle: "CSV 适合使用 Excel 编辑，JSON 备份包含全部面试和待办") {
                    HStack(spacing: 12) {
                        dataAction("导出 CSV", icon: "tablecells", action: exportCSV)
                        dataAction("导入 CSV", icon: "square.and.arrow.down", action: importCSV)
                        dataAction("完整备份", icon: "externaldrive", action: exportBackup)
                        dataAction("恢复备份", icon: "arrow.clockwise.icloud", action: importBackup)
                    }
                    Text("CSV 必须包含“公司”和“岗位”列；重复导入的同一投递会自动跳过。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SectionCard("本地自动备份", subtitle: "每次数据保存成功后生成快照，滚动保留最近 \(BackupService.maximumRollingBackupCount) 份") {
                    HStack {
                        Label("上次成功备份", systemImage: "externaldrive.badge.checkmark")
                            .font(.headline)
                        Spacer()
                        Text(store.lastSuccessfulBackupAt.map { AppFormatters.fullDate.string(from: $0) } ?? "尚无备份")
                            .foregroundStyle(store.lastSuccessfulBackupAt == nil ? .secondary : .primary)
                    }
                    if let error = store.lastBackupError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Divider()
                    if store.localBackups.isEmpty {
                        Text("下次成功保存数据时会自动创建第一份备份。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.localBackups.prefix(5)) { backup in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(AppFormatters.fullDate.string(from: backup.createdAt))
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(backup.byteCount), countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("恢复此版本") { pendingBackupURL = backup.url }
                                    .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 2)
                        }
                        if store.localBackups.count > 5 {
                            Text("还有 \(store.localBackups.count - 5) 份较早备份，系统会自动滚动清理。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionCard("自定义流程状态", subtitle: "创建适合自己求职流程的看板列") {
                    HStack {
                        TextField("状态名称，例如等待 HC", text: $newStageName)
                        colorPicker(selection: $newStageColor)
                        Picker("分析分类", selection: $newStageAnalysisCategory) {
                            ForEach(ApplicationAnalysisCategory.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .frame(width: 120)
                        Toggle("终态", isOn: $newStageIsTerminal)
                            .toggleStyle(.checkbox)
                        Button("添加") {
                            store.addCustomStage(
                                name: newStageName,
                                colorKey: newStageColor,
                                isTerminal: newStageIsTerminal,
                                analysisCategory: newStageAnalysisCategory
                            )
                            newStageName = ""
                            newStageIsTerminal = false
                            newStageAnalysisCategory = .submitted
                        }
                        .disabled(newStageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if store.customStages.isEmpty {
                        Text("暂无自定义状态。标准状态会继续保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.customStages.sorted { $0.order < $1.order }) { stage in
                            HStack {
                                Circle().fill(Color.jobColor(stage.colorKey)).frame(width: 9, height: 9)
                                Text(stage.name)
                                if stage.isTerminal {
                                    Text("终态").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("分析分类", selection: Binding(
                                    get: { store.customStage(id: stage.id)?.analysisCategory ?? stage.analysisCategory },
                                    set: { store.updateCustomStageCategory(id: stage.id, to: $0) }
                                )) {
                                    ForEach(ApplicationAnalysisCategory.allCases) { category in
                                        Text(category.rawValue).tag(category)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 105)
                                .help("该状态在概览和数据分析中的统计分类")
                                Text("\(store.applications.filter { $0.customStageID == stage.id }.count) 条投递")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    deleteTarget = .stage(stage)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                SectionCard("岗位标签", subtitle: "标签可以在投递列表中筛选，一个岗位可使用多个标签") {
                    HStack {
                        TextField("标签名称", text: $newTagName)
                        colorPicker(selection: $newTagColor)
                        Button("添加") {
                            store.addTag(name: newTagName, colorKey: newTagColor)
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if store.tags.isEmpty {
                        Text("暂无标签。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(store.tags) { tag in
                                HStack(spacing: 3) {
                                    TagPill(tag: tag)
                                    Button {
                                        deleteTarget = .tag(tag)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                SectionCard("数据概况") {
                    HStack(spacing: 30) {
                        dataCount("公司", store.companies.count)
                        dataCount("招聘项目", store.projects.count)
                        dataCount("投递", store.applications.count)
                        dataCount("流程事件", store.events.count)
                        dataCount("待办", store.todos.count)
                        dataCount("简历版本", store.resumeVersions.count)
                    }
                }

                SectionCard("关于秋招助手") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("秋招助手 MVP").font(.headline)
                        Text("原生 macOS 求职进度管理工具。所有数据默认保存在当前 Mac，不会上传到外部服务器。")
                            .foregroundStyle(.secondary)
                        Text("建议定期使用“完整备份”，将 JSON 文件保存到你的云盘或其他安全位置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("设置")
        .onAppear { localSettings = store.settings }
        .task { await syncNotificationAuthorization() }
        .alert("操作结果", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("确认删除？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { target in
            Button("删除", role: .destructive) {
                switch target {
                case .stage(let stage): store.deleteCustomStage(id: stage.id)
                case .tag(let tag): store.deleteTag(id: tag.id)
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { target in
            switch target {
            case .stage:
                Text("使用该状态的投递将恢复为原来的标准状态。")
            case .tag:
                Text("该标签会从所有投递记录中移除。")
            }
        }
        .alert("恢复完整备份？", isPresented: Binding(
            get: { pendingBackupURL != nil },
            set: { if !$0 { pendingBackupURL = nil } }
        ), presenting: pendingBackupURL) { url in
            Button("恢复并替换", role: .destructive) {
                pendingBackupURL = nil
                restoreBackup(from: url)
            }
            Button("取消", role: .cancel) { pendingBackupURL = nil }
        } message: { _ in
            Text("当前的全部公司、投递、日程和待办将被备份内容替换。恢复前会先自动保留当前版本，恢复成功前不会覆盖本地数据。")
        }
    }

    private func dataAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func colorPicker(selection: Binding<String>) -> some View {
        Picker("颜色", selection: selection) {
            ForEach(colorOptions, id: \.self) { key in
                HStack {
                    Circle().fill(Color.jobColor(key)).frame(width: 8, height: 8)
                    Text(colorName(key))
                }
                .tag(key)
            }
        }
        .labelsHidden()
        .frame(width: 100)
    }

    private func colorName(_ key: String) -> String {
        switch key {
        case "red": return "红色"
        case "orange": return "橙色"
        case "yellow": return "黄色"
        case "green": return "绿色"
        case "teal": return "青色"
        case "blue": return "蓝色"
        case "purple": return "紫色"
        case "pink": return "粉色"
        case "gray": return "灰色"
        default: return "靛蓝"
        }
    }

    private func dataCount(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)").font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func saveSettings(refreshReminders: Bool = true) {
        store.updateSettings(localSettings)
        guard store.lastSaveError == nil else {
            resultMessage = store.lastSaveError
            return
        }
        guard refreshReminders else {
            resultMessage = "后台节能设置已保存。"
            return
        }
        Task {
            await ReminderService.refresh(store: store)
            resultMessage = store.lastNotificationError ?? "提醒偏好已保存。"
        }
    }

    private func requestNotifications() {
        isRequestingNotifications = true
        Task {
            let granted = await ReminderService.requestAuthorization()
            await MainActor.run {
                isRequestingNotifications = false
                localSettings.notificationsEnabled = granted
                store.updateSettings(localSettings)
                if let error = store.lastSaveError {
                    resultMessage = error
                } else {
                    resultMessage = granted ? "系统通知已开启。" : "未获得通知权限。你可以在“系统设置 → 通知”中允许秋招助手发送通知。"
                }
            }
            if granted, store.lastSaveError == nil {
                await ReminderService.refresh(store: store)
                if let error = store.lastNotificationError { resultMessage = error }
            }
        }
    }

    private func syncNotificationAuthorization() async {
        guard store.settings.notificationsEnabled else { return }
        guard !(await ReminderService.isAuthorized()) else { return }
        var updatedSettings = store.settings
        updatedSettings.notificationsEnabled = false
        localSettings = updatedSettings
        store.updateSettings(updatedSettings)
        if store.lastSaveError == nil {
            await ReminderService.refresh(store: store)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "导出投递记录"
        panel.nameFieldStringValue = "秋招投递记录.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVService.export(applications: store.applications, store: store).write(to: url, options: .atomic)
            resultMessage = "已导出 \(store.applications.count) 条投递记录。"
        } catch {
            resultMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "导入投递记录"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let forms = try await Task.detached(priority: .userInitiated) {
                    let data = try readImportData(
                        at: url,
                        maximumBytes: AppDataLimits.maximumCSVBytes,
                        label: "CSV"
                    )
                    return try CSVService.decode(data)
                }.value
                let result = try store.importApplications(forms)
                if result.skippedDuplicateCount > 0 {
                    resultMessage = "成功导入 \(result.importedCount) 条，跳过 \(result.skippedDuplicateCount) 条重复投递。"
                } else {
                    resultMessage = "成功导入 \(result.importedCount) 条投递记录。"
                }
            } catch {
                resultMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "备份全部求职数据"
        panel.nameFieldStringValue = "秋招助手完整备份.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BackupService.encode(store.currentSnapshot()).write(to: url, options: .atomic)
            resultMessage = "完整备份已保存。"
        } catch {
            resultMessage = "备份失败：\(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择秋招助手备份"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingBackupURL = url
    }

    private func restoreBackup(from url: URL) {
        Task {
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    let data = try readImportData(
                        at: url,
                        maximumBytes: AppDataLimits.maximumBackupBytes,
                        label: "备份"
                    )
                    return try BackupService.decode(data)
                }.value
                try store.replace(with: snapshot)
                localSettings = store.settings
                await ReminderService.refresh(store: store)
                resultMessage = store.lastNotificationError ?? "备份已恢复，共 \(snapshot.applications.count) 条投递记录。"
            } catch {
                resultMessage = "恢复失败：\(error.localizedDescription)"
            }
        }
    }
}

private func readImportData(at url: URL, maximumBytes: Int, label: String) throws -> Data {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    if let fileSize = values.fileSize, fileSize > maximumBytes {
        throw ImportFileError.tooLarge(label: label, megabytes: maximumBytes / 1_024 / 1_024)
    }
    return try Data(contentsOf: url, options: .mappedIfSafe)
}

import SwiftUI

private enum ApplicationEditorOptions {
    static let industries = [
        "互联网", "软件/信息技术", "银行", "金融", "制造业", "消费品/零售", "咨询",
        "医疗/医药", "教育", "房地产/建筑", "能源/化工", "交通/物流", "文化传媒", "政府/公共事业"
    ]
    static let companyNatures = ["央企", "国企", "民企", "外企", "合资企业", "事业单位"]
    static let projectTypes = ["秋招", "提前批", "春招", "校招", "暑期实习", "日常实习", "补录", "社招"]
    static let positionCategories = ["研发", "算法", "数据", "产品", "设计", "测试", "运营", "市场", "销售", "职能", "管培生"]
    static let locations = ["北京", "上海", "深圳", "广州", "杭州", "成都", "南京", "武汉", "西安", "苏州", "天津", "重庆", "全国", "远程"]
    static let channels = ["官网", "内推", "招聘平台", "招聘会", "校园宣讲", "学校就业网", "邮件", "猎头"]
}

struct ApplicationEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let application: JobApplication?
    @State private var form = ApplicationFormData()
    @State private var hasAppliedDate = false
    @State private var hasProjectDeadline = false
    @State private var didLoad = false
    @State private var isQuickMode = true
    @State private var jdParseTask: Task<Void, Never>?
    @State private var jdParseMessage = ""
    @State private var duplicateCandidates: [JobApplication] = []
    @State private var showingDuplicateConfirmation = false

    init(application: JobApplication? = nil) {
        self.application = application
    }

    private var canSave: Bool {
        !form.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !form.position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(application == nil ? "新建投递" : "编辑投递")
                        .font(.title2.bold())
                    Text("公司和岗位为必填项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(20)
            Divider()
            Form {
                if application == nil {
                    Section {
                        Picker("填写模式", selection: $isQuickMode) {
                            Text("快速新建").tag(true)
                            Text("完整填写").tag(false)
                        }
                        .pickerStyle(.segmented)
                        Text(isQuickMode ? "只需公司、岗位和 JD，其他信息可保存后再补充。" : "一次完成公司、项目、进度和标签等信息。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if application == nil && isQuickMode { quickForm } else { fullForm }
            }
            .formStyle(.grouped)
        }
        .frame(width: 680, height: 760)
        .onAppear(perform: loadIfNeeded)
        .onDisappear { jdParseTask?.cancel() }
        .onChange(of: hasAppliedDate) { _, enabled in
            if enabled, form.appliedAt == nil { form.appliedAt = Date() }
            if !enabled { form.appliedAt = nil }
        }
        .onChange(of: hasProjectDeadline) { _, enabled in
            if enabled, form.projectDeadline == nil {
                form.projectDeadline = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            }
            if !enabled { form.projectDeadline = nil }
        }
        .onChange(of: form.jdText) { _, newValue in scheduleAutomaticJDParsing(newValue) }
        .confirmationDialog("发现可能重复的投递", isPresented: $showingDuplicateConfirmation, titleVisibility: .visible) {
            ForEach(duplicateCandidates.prefix(3)) { duplicate in
                Button("合并到「\(store.company(for: duplicate)?.name ?? "未知公司") · \(duplicate.position)」") {
                    merge(into: duplicate)
                }
            }
            Button("仍然创建新投递") { persistNewApplication() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("公司和岗位与已有记录相似。合并只会补齐缺失信息，不会重置已有进度。")
        }
    }

    @ViewBuilder
    private var quickForm: some View {
        Section("必填信息") {
            companyNameField
            TextField("岗位名称", text: $form.position)
            TextField("JD 链接（选填）", text: $form.jdURL)
        }
        jdSection(minimumHeight: 260)
        if hasParsedMetadata {
            Section("自动识别结果") {
                if !form.location.isEmpty { LabeledContent("工作地点", value: form.location) }
                if !form.category.isEmpty { LabeledContent("岗位类别", value: form.category) }
                if let deadline = form.projectDeadline {
                    LabeledContent("截止时间", value: AppFormatters.fullDate.string(from: deadline))
                }
                if !form.requirements.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("岗位要求").font(.caption).foregroundStyle(.secondary)
                        Text(form.requirements).lineLimit(4).textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fullForm: some View {
        Section("公司") {
            companyNameField
            PresetTextField("所属行业", value: $form.companyIndustry, options: ApplicationEditorOptions.industries, customPrompt: "输入自定义行业")
            PresetTextField("公司性质", value: $form.companyNature, options: ApplicationEditorOptions.companyNatures, customPrompt: "输入自定义公司性质")
            TextField("公司官网", text: $form.companyWebsite)
            TextField("招聘官网", text: $form.recruitmentURL)
        }
        Section("招聘项目") {
            TextField("项目名称，例如 2027 届秋季校园招聘", text: $form.projectName)
            PresetTextField("项目类型", value: $form.projectType, options: ApplicationEditorOptions.projectTypes, customPrompt: "输入自定义项目类型")
            TextField("项目链接", text: $form.projectURL)
            Toggle("设置项目截止时间", isOn: $hasProjectDeadline)
            if hasProjectDeadline {
                DatePicker("截止时间", selection: Binding(
                    get: { form.projectDeadline ?? Date() },
                    set: { form.projectDeadline = $0 }
                ))
            }
        }
        Section("岗位") {
            TextField("岗位名称", text: $form.position)
            PresetTextField("岗位类别", value: $form.category, options: ApplicationEditorOptions.positionCategories, customPrompt: "输入自定义岗位类别")
            TextField("部门或事业群", text: $form.department)
            PresetTextField("工作地点", value: $form.location, options: ApplicationEditorOptions.locations, customPrompt: "输入其他城市或多个地点")
            TextField("JD 链接", text: $form.jdURL)
            PresetTextField("投递渠道", value: $form.channel, options: ApplicationEditorOptions.channels, customPrompt: "输入自定义投递渠道")
            TextField("内推人或联系人", text: $form.referrer)
        }
        jdSection(minimumHeight: 150)
        Section("岗位要求") { TextEditor(text: $form.requirements).frame(minHeight: 100) }
        Section("进度") {
            Picker("标准状态", selection: $form.status) {
                ForEach(ApplicationStatus.allCases) { status in Text(status.rawValue).tag(status) }
            }
            if !store.customStages.isEmpty {
                Picker("自定义状态", selection: $form.customStageID) {
                    Text("使用标准状态").tag(nil as UUID?)
                    ForEach(store.customStages.sorted { $0.order < $1.order }) { stage in Text(stage.name).tag(stage.id as UUID?) }
                }
            }
            Picker("优先级", selection: $form.priority) {
                ForEach(Priority.allCases) { priority in Text(priority.rawValue).tag(priority) }
            }
            Toggle("已经投递", isOn: $hasAppliedDate)
            if hasAppliedDate {
                DatePicker("投递时间", selection: Binding(
                    get: { form.appliedAt ?? Date() },
                    set: { form.appliedAt = $0 }
                ))
            }
            TextField("薪资信息", text: $form.salary)
        }
        Section("标签与简历") {
            if store.tags.isEmpty {
                Text("可以在设置中创建岗位标签").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                    ForEach(store.tags) { tag in
                        Toggle(tag.name, isOn: Binding(
                            get: { form.tagIDs.contains(tag.id) },
                            set: { enabled in
                                if enabled { form.tagIDs.insert(tag.id) } else { form.tagIDs.remove(tag.id) }
                            }
                        )).toggleStyle(.checkbox)
                    }
                }
            }
            Picker("使用的简历", selection: $form.resumeVersionID) {
                Text("未指定").tag(nil as UUID?)
                ForEach(store.resumeVersions.sorted { $0.updatedAt > $1.updatedAt }) { resume in Text(resume.name).tag(resume.id as UUID?) }
            }
        }
        Section("备注") { TextEditor(text: $form.notes).frame(minHeight: 100) }
    }

    private var companyNameField: some View {
        HStack {
            TextField("公司名称", text: $form.companyName)
            if !store.companies.isEmpty {
                Menu {
                    ForEach(store.companies.sorted { $0.name < $1.name }) { company in
                        Button(company.name) { apply(company) }
                    }
                } label: { Image(systemName: "chevron.down") }
                .menuStyle(.borderlessButton)
                .help("选择已有公司")
            }
        }
    }

    private func jdSection(minimumHeight: CGFloat) -> some View {
        Section("JD 原文") {
            TextEditor(text: $form.jdText)
                .frame(minHeight: minimumHeight)
                .overlay(alignment: .topLeading) {
                    if form.jdText.isEmpty {
                        Text("粘贴完整 JD，自动识别公司、岗位、地点、类别、截止时间和岗位要求")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                if !jdParseMessage.isEmpty {
                    Label(jdParseMessage, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新识别") { parseJD(overwrite: true) }
                    .disabled(form.jdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var hasParsedMetadata: Bool {
        !form.location.isEmpty || !form.category.isEmpty || form.projectDeadline != nil || !form.requirements.isEmpty
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let application {
            form = store.formData(for: application)
            isQuickMode = false
            hasAppliedDate = form.appliedAt != nil
            hasProjectDeadline = form.projectDeadline != nil
        } else {
            form.projectType = ""
        }
        didLoad = true
    }

    private func apply(_ company: Company) {
        form.selectedCompanyID = company.id
        form.companyName = company.name
        form.companyIndustry = company.industry
        form.companyNature = company.nature
        form.companyWebsite = company.website
        form.recruitmentURL = company.recruitmentURL
        form.selectedProjectID = nil
        form.projectName = ""
        form.projectType = ""
        form.projectURL = ""
        form.projectDeadline = nil
        hasProjectDeadline = false
        if let project = store.projects
            .filter({ $0.companyID == company.id })
            .sorted(by: { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) })
            .first {
            form.selectedProjectID = project.id
            form.projectName = project.name
            form.projectType = project.type
            form.projectURL = project.url
            form.projectDeadline = project.deadline
            hasProjectDeadline = project.deadline != nil
        }
    }

    private func save() {
        if let application {
            persist(applicationID: application.id)
            return
        }
        duplicateCandidates = store.possibleDuplicateApplications(for: form)
        if duplicateCandidates.isEmpty { persistNewApplication() } else { showingDuplicateConfirmation = true }
    }

    private func persistNewApplication() { persist(applicationID: nil) }

    private func persist(applicationID: UUID?) {
        store.saveApplication(id: applicationID, data: form)
        guard store.lastSaveError == nil else { return }
        Task { await ReminderService.refresh(store: store) }
        dismiss()
    }

    private func merge(into duplicate: JobApplication) {
        store.mergeApplication(id: duplicate.id, with: form)
        guard store.lastSaveError == nil else { return }
        Task { await ReminderService.refresh(store: store) }
        dismiss()
    }

    private func scheduleAutomaticJDParsing(_ text: String) {
        guard application == nil, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 else { return }
        jdParseTask?.cancel()
        jdParseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            parseJD(overwrite: false)
        }
    }

    private func parseJD(overwrite: Bool) {
        let result = JDParsingService.analyze(form.jdText)
        if (overwrite || form.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), !result.companyName.isEmpty { form.companyName = result.companyName }
        if (overwrite || form.position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), !result.position.isEmpty { form.position = result.position }
        if (overwrite || form.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), !result.location.isEmpty { form.location = result.location }
        if (overwrite || form.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), !result.category.isEmpty { form.category = result.category }
        if (overwrite || form.projectDeadline == nil), let deadline = result.deadline {
            form.projectDeadline = deadline
            hasProjectDeadline = true
        }
        if (overwrite || form.requirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), !result.requirements.isEmpty { form.requirements = result.requirements }
        jdParseMessage = result.recognizedFieldCount > 0 ? "已识别 \(result.recognizedFieldCount) 项信息" : "未识别到明确字段，可手动填写"
    }
}

private struct PresetTextField: View {
    private enum Selection: Hashable {
        case unspecified
        case preset(String)
        case custom
    }

    private let title: String
    private let options: [String]
    private let customPrompt: String
    @Binding private var value: String
    @State private var isChoosingCustom: Bool

    init(_ title: String, value: Binding<String>, options: [String], customPrompt: String) {
        self.title = title
        self.options = options
        self.customPrompt = customPrompt
        _value = value
        _isChoosingCustom = State(initialValue: Self.selection(for: value.wrappedValue, options: options) == .custom)
    }

    var body: some View {
        Group {
            Picker(title, selection: Binding(get: { currentSelection }, set: { updateSelection($0) })) {
                Text("请选择").tag(Selection.unspecified)
                ForEach(options, id: \.self) { option in Text(option).tag(Selection.preset(option)) }
                Divider()
                Text("自定义").tag(Selection.custom)
            }
            if currentSelection == .custom { TextField(customPrompt, text: $value) }
        }
        .onChange(of: value) { _, newValue in
            switch Self.selection(for: newValue, options: options) {
            case .custom: isChoosingCustom = true
            case .preset: isChoosingCustom = false
            case .unspecified: break
            }
        }
    }

    private var currentSelection: Selection {
        isChoosingCustom ? .custom : Self.selection(for: value, options: options)
    }

    private func updateSelection(_ newSelection: Selection) {
        switch newSelection {
        case .unspecified:
            isChoosingCustom = false
            value = ""
        case let .preset(option):
            isChoosingCustom = false
            value = option
        case .custom:
            isChoosingCustom = true
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedValue.isEmpty || options.contains(normalizedValue) { value = "" }
        }
    }

    private static func selection(for value: String, options: [String]) -> Selection {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedValue.isEmpty { return .unspecified }
        if options.contains(normalizedValue) { return .preset(normalizedValue) }
        return .custom
    }
}

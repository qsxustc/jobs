import AppKit
import SwiftUI

struct MailRecognitionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sourceText = ""
    @State private var draft = MailNoticeAnalysis()
    @State private var hasAnalysis = false
    @State private var selectedApplicationID: UUID?
    @State private var applicationSearchText = ""
    @State private var recognizedCompanyName = ""
    @State private var recognizedPosition = ""
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var isSaving = false
    @State private var didSave = false

    private let supportedTypes: [EventType] = [.interview, .hrInterview, .writtenTest, .assessment, .other]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 16) {
                    sourceCard
                        .frame(minWidth: 320, maxWidth: 430)

                    if hasAnalysis {
                        resultCard
                            .frame(minWidth: 400, maxWidth: .infinity)
                    } else {
                        SectionCard("等待识别", subtitle: "复制邮件正文后点击左侧按钮") {
                            EmptyStateView(
                                icon: "envelope.open",
                                title: "还没有识别结果",
                                message: "支持中文面试、笔试和在线测评通知。"
                            )
                        }
                        .frame(minWidth: 400, maxWidth: .infinity)
                    }
                }

            }
            .padding(22)
        }
        .navigationTitle("邮件识别")
        .alert("无法读取邮件内容", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: selectedApplicationID) { _, applicationID in
            applySelectedApplication(applicationID)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("从邮件提取招聘日程")
                    .font(.title2.bold())
                Text("复制邮件正文，一次点击即可识别通知类型、公司岗位、时间、地点和会议链接。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("仅在本机解析", systemImage: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.7), in: Capsule())
        }
    }

    private var sourceCard: some View {
        SectionCard("邮件内容", subtitle: "可直接读取剪贴板，也可在下方粘贴或修改") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: readClipboardAndAnalyze) {
                    Label("读取剪贴板并识别", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack {
                    Button("识别当前内容", action: analyzeCurrentText)
                        .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("清空", action: clear)
                        .disabled(sourceText.isEmpty && !hasAnalysis)
                    Spacer()
                    Text("\(sourceText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LargeTextEditor(
                    text: $sourceText,
                    minimumHeight: 430,
                    placeholder: "复制邮件后点击“读取剪贴板并识别”"
                )
            }
        }
    }

    private var resultCard: some View {
        SectionCard("识别结果", subtitle: "保存前请核对，所有字段都可以修改") {
            VStack(alignment: .leading, spacing: 16) {
                analysisSummary
                Divider()
                recognitionEditor

                if !draft.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("识别提示")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(draft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Divider()
                saveArea
            }
        }
    }

    private var analysisSummary: some View {
        HStack(spacing: 12) {
            Label(
                draft.isLikelyNotice ? "识别为招聘日程通知" : "暂不能确认是新的日程通知",
                systemImage: draft.isLikelyNotice ? "checkmark.seal.fill" : "questionmark.diamond.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(draft.isLikelyNotice ? Color.green : Color.orange)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("置信度 \(draft.confidence)%")
                    .font(.caption.weight(.semibold))
                ProgressView(value: Double(draft.confidence), total: 100)
                    .frame(width: 96)
                    .tint(confidenceColor)
            }
        }
    }

    private var recognitionEditor: some View {
        VStack(alignment: .leading, spacing: 11) {
            MailEditorRow("通知类型") {
                Picker("通知类型", selection: $draft.type) {
                    ForEach(supportedTypes) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            MailEditorRow("日程标题") {
                TextField("例如：一面 · 技术面", text: $draft.title)
            }

            if draft.type.isInterview {
                MailEditorRow("面试轮次") {
                    Toggle("记录轮次", isOn: Binding(
                        get: { draft.round != nil },
                        set: { enabled in draft.round = enabled ? (draft.round ?? 1) : nil }
                    ))
                    if draft.round != nil {
                        Stepper("第 \(draft.round ?? 1) 轮", value: Binding(
                            get: { draft.round ?? 1 },
                            set: { draft.round = $0 }
                        ), in: 1...20)
                    }
                }
            }

            MailEditorRow("关联投递") {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        TextField("搜索已有公司的投递或岗位", text: $applicationSearchText)
                            .textFieldStyle(.roundedBorder)
                        if !applicationSearchText.isEmpty {
                            Button {
                                applicationSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("清除搜索")
                        }
                    }

                    Picker("关联投递", selection: $selectedApplicationID) {
                        Text("不关联，保存时新建投递").tag(nil as UUID?)
                        if !filteredApplicationOptions.isEmpty {
                            Divider()
                            ForEach(filteredApplicationOptions) { application in
                                Text(applicationLabel(application)).tag(application.id as UUID?)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if selectedApplicationID == nil && !likelyApplicationOptions.isEmpty {
                        candidateButtons(
                            title: "可能的投递",
                            labels: likelyApplicationOptions.map(applicationLabel),
                            action: selectSuggestedApplication(at:)
                        )
                    } else if !applicationSearchText.isEmpty && filteredApplicationOptions.isEmpty {
                        Text("没有匹配的已有投递，可继续在下方填写公司和岗位来新建投递。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MailEditorRow("公司") {
                VStack(alignment: .leading, spacing: 7) {
                    TextField("搜索已有公司，或直接输入公司名称", text: $draft.companyName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(selectedApplicationID != nil)

                    if selectedApplicationID == nil && !suggestedCompanyNames.isEmpty {
                        candidateButtons(
                            title: "可能的公司",
                            labels: suggestedCompanyNames,
                            action: selectSuggestedCompany(at:)
                        )
                    }

                    if selectedApplicationID == nil {
                        Text("输入时会优先显示邮件中的名称和已有公司的近似结果；没有结果也可直接新建。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MailEditorRow("岗位") {
                TextField("未识别，可手动填写", text: $draft.position)
                    .disabled(selectedApplicationID != nil)
            }

            if selectedApplicationID != nil {
                Label("公司和岗位已按关联投递自动填充。若需修改，请编辑该投递记录或取消关联。", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 88)
            }

            MailEditorRow("开始时间") {
                if draft.startsAt != nil {
                    DatePicker("开始时间", selection: startDateBinding)
                        .labelsHidden()
                    Button {
                        draft.startsAt = nil
                        draft.endsAt = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清除时间")
                } else {
                    Button("设置时间") { draft.startsAt = defaultStartDate }
                        .buttonStyle(.bordered)
                    Text("保存日程前必须设置")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            MailEditorRow("结束时间") {
                Toggle("设置结束时间", isOn: Binding(
                    get: { draft.endsAt != nil },
                    set: { enabled in
                        if enabled {
                            draft.endsAt = (draft.startsAt ?? defaultStartDate).addingTimeInterval(3_600)
                        } else {
                            draft.endsAt = nil
                        }
                    }
                ))
                if draft.endsAt != nil {
                    DatePicker("结束时间", selection: endDateBinding)
                        .labelsHidden()
                }
            }

            MailEditorRow("进行形式") {
                Picker("进行形式", selection: $draft.format) {
                    ForEach(InterviewFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            MailEditorRow("会议链接") {
                TextField("线上会议或作答链接", text: $draft.meetingURL)
            }

            MailEditorRow("地点") {
                TextField("线下面试或考试地点", text: $draft.location)
            }

            MailEditorRow("联系人") {
                TextField("面试官、HR 或联系人", text: $draft.interviewer)
            }
        }
    }

    private var saveArea: some View {
        VStack(alignment: .leading, spacing: 11) {
            if store.activeApplications.isEmpty {
                Label("当前没有投递记录，将使用识别出的公司和岗位新建投递。", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedApplicationID == nil && !canCreateApplication {
                Label("新建投递需要公司和岗位名称。也可以选择一条已有投递。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let startsAt = draft.startsAt, let endsAt = draft.endsAt, endsAt < startsAt {
                Label("结束时间不能早于开始时间。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            } else if let duplicate = matchingDuplicateEvent {
                Label(
                    "该投递在 \(duplicate.startsAt.formatted(date: .abbreviated, time: .shortened)) 已有同类型日程，已阻止重复保存。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }

            HStack {
                Text("保存后会使用默认的提前 1 天、2 小时提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: saveRecognizedEvent) {
                    Label(saveButtonTitle, systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
    }

    private var confidenceColor: Color {
        if draft.confidence >= 80 { return .green }
        if draft.confidence >= 55 { return .orange }
        return .red
    }

    private var applicationOptions: [JobApplication] {
        store.activeApplications.sorted {
            let leftCompany = store.company(for: $0)?.name ?? ""
            let rightCompany = store.company(for: $1)?.name ?? ""
            if leftCompany != rightCompany { return leftCompany < rightCompany }
            return $0.position < $1.position
        }
    }

    private var companyOptions: [Company] {
        store.companies.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var filteredApplicationOptions: [JobApplication] {
        let query = applicationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return applicationOptions }
        return applicationOptions.filter { application in
            let companyName = store.company(for: application)?.name ?? ""
            return application.id == selectedApplicationID ||
                application.position.localizedCaseInsensitiveContains(query) ||
                query.localizedCaseInsensitiveContains(application.position) ||
                companyName.localizedCaseInsensitiveContains(query) ||
                query.localizedCaseInsensitiveContains(companyName)
        }
    }

    private var rankedApplicationMatches: [MailApplicationMatch] {
        MailNoticeMatchingService.rankedApplicationMatches(
            for: draft,
            applications: applicationOptions,
            companies: store.companies
        )
    }

    private var likelyApplicationOptions: [JobApplication] {
        Array(rankedApplicationMatches.prefix(4)).compactMap { match in
            store.application(id: match.applicationID)
        }
    }

    private var suggestedCompanyNames: [String] {
        let current = draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return MailNoticeMatchingService.suggestedCompanyNames(
            for: draft,
            companies: companyOptions,
            query: current
        )
        .filter { $0.caseInsensitiveCompare(current) != .orderedSame }
    }

    private var canCreateApplication: Bool {
        !draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        guard !isSaving,
              !didSave,
              hasAnalysis,
              let startsAt = draft.startsAt,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedApplicationID != nil || canCreateApplication else { return false }
        if let endsAt = draft.endsAt, endsAt < startsAt { return false }
        return matchingDuplicateEvent == nil
    }

    private var saveButtonTitle: String {
        if isSaving { return "保存中…" }
        if didSave { return "已保存" }
        if matchingDuplicateEvent != nil { return "日程已存在" }
        return selectedApplicationID == nil ? "新建投递并保存" : "保存到投递流程"
    }

    private var matchingDuplicateEvent: ProcessEvent? {
        guard let selectedApplicationID, let startsAt = draft.startsAt else { return nil }
        return store.duplicateEvent(
            applicationID: selectedApplicationID,
            type: draft.type,
            startsAt: startsAt
        )
    }

    private var defaultStartDate: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { draft.startsAt ?? defaultStartDate },
            set: { newValue in
                draft.startsAt = newValue
                if let end = draft.endsAt, end < newValue {
                    draft.endsAt = newValue.addingTimeInterval(3_600)
                }
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { draft.endsAt ?? (draft.startsAt ?? defaultStartDate).addingTimeInterval(3_600) },
            set: { draft.endsAt = $0 }
        )
    }

    private func readClipboardAndAnalyze() {
        guard let clipboardText = clipboardText(),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "剪贴板里没有可读取的文字。请先在邮件中复制正文，再点击识别。"
            return
        }
        sourceText = clipboardText
        analyzeCurrentText()
    }

    private func clipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        if let value = pasteboard.string(forType: .string), !value.isEmpty { return value }
        guard let htmlData = pasteboard.data(forType: .html) else { return nil }
        return try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ).string
    }

    private func analyzeCurrentText() {
        let normalized = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            errorMessage = "请先复制或粘贴邮件正文。"
            return
        }
        draft = MailNoticeParser.analyze(normalized)
        hasAnalysis = true
        recognizedCompanyName = draft.companyName
        recognizedPosition = draft.position
        let matches = MailNoticeMatchingService.rankedApplicationMatches(
            for: draft,
            applications: applicationOptions,
            companies: store.companies
        )
        let suggestion = MailNoticeMatchingService.automaticApplicationID(from: matches)
        applicationSearchText = draft.companyName
        selectedApplicationID = suggestion
        if let suggestion {
            applySelectedApplication(suggestion)
        } else {
            restoreRecognizedApplicationFields()
        }
        savedMessage = nil
        didSave = false
        isSaving = false
    }

    private func applicationLabel(_ application: JobApplication) -> String {
        let company = store.company(for: application)?.name ?? "未知公司"
        return "\(company) · \(application.position)"
    }

    private func applySelectedApplication(_ applicationID: UUID?) {
        guard let applicationID else {
            restoreRecognizedApplicationFields()
            return
        }
        guard let application = store.application(id: applicationID) else {
            selectedApplicationID = nil
            return
        }
        draft.companyName = store.company(for: application)?.name ?? ""
        draft.position = application.position
        applicationSearchText = draft.companyName
        savedMessage = nil
    }

    private func restoreRecognizedApplicationFields() {
        draft.companyName = recognizedCompanyName
        draft.position = recognizedPosition
    }

    private func selectSuggestedApplication(at index: Int) {
        guard likelyApplicationOptions.indices.contains(index) else { return }
        selectedApplicationID = likelyApplicationOptions[index].id
    }

    private func selectSuggestedCompany(at index: Int) {
        guard selectedApplicationID == nil, suggestedCompanyNames.indices.contains(index) else { return }
        let name = suggestedCompanyNames[index]
        draft.companyName = name
        recognizedCompanyName = name
        applicationSearchText = name
        savedMessage = nil
    }

    @ViewBuilder
    private func candidateButtons(
        title: String,
        labels: [String],
        action: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Button(label) { action(index) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func saveRecognizedEvent() {
        guard canSave, let startsAt = draft.startsAt else { return }
        isSaving = true
        defer { isSaving = false }
        let applicationID: UUID
        if let selectedApplicationID {
            applicationID = selectedApplicationID
        } else {
            var form = ApplicationFormData()
            form.companyName = draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
            form.position = draft.position.trimmingCharacters(in: .whitespacesAndNewlines)
            form.channel = "邮件"
            form.status = draft.type.isInterview ? .interviewing : .assessment
            form.notes = "由招聘通知邮件识别创建，请补充投递信息。"
            applicationID = store.saveApplication(data: form)
            guard store.lastSaveError == nil else { return }
            selectedApplicationID = applicationID
        }

        var eventForm = EventFormData()
        eventForm.type = draft.type
        eventForm.title = draft.title
        eventForm.round = draft.type.isInterview ? draft.round : nil
        eventForm.startsAt = startsAt
        eventForm.endsAt = draft.endsAt
        eventForm.format = draft.format
        eventForm.meetingURL = draft.meetingURL
        eventForm.location = draft.location
        eventForm.interviewer = draft.interviewer
        eventForm.result = .scheduled
        eventForm.reminderMinutes = [1_440, 120]
        eventForm.notes = sourceNote(from: draft.sourceText)
        store.saveEvent(applicationID: applicationID, data: eventForm)
        guard store.lastSaveError == nil else { return }

        let label = store.application(id: applicationID).map(applicationLabel) ?? "投递流程"
        savedMessage = "已保存到 \(label)，无需再次点击。"
        didSave = true
        Task { await ReminderService.refresh(store: store) }
    }

    private func sourceNote(from text: String) -> String {
        let maximumLength = 8_000
        let clipped = String(text.prefix(maximumLength))
        let suffix = text.count > maximumLength ? "\n\n（原文过长，已截取前 \(maximumLength) 字）" : ""
        return "由邮件识别导入，请以邮件原文为准。\n\n原始邮件：\n\(clipped)\(suffix)"
    }

    private func clear() {
        sourceText = ""
        draft = MailNoticeAnalysis()
        hasAnalysis = false
        selectedApplicationID = nil
        applicationSearchText = ""
        recognizedCompanyName = ""
        recognizedPosition = ""
        savedMessage = nil
        isSaving = false
        didSave = false
    }
}

private struct MailEditorRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

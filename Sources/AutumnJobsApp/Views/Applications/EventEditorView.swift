import SwiftUI

struct EventEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let applicationID: UUID
    let event: ProcessEvent?
    @State private var form = EventFormData()
    @State private var hasEndTime = false
    @State private var hasRound = true
    @State private var didLoad = false

    init(applicationID: UUID, event: ProcessEvent? = nil) {
        self.applicationID = applicationID
        self.event = event
    }

    private var canSave: Bool {
        guard !form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let endsAt = form.endsAt else { return true }
        return endsAt >= form.startsAt
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(event == nil ? "添加流程" : "编辑流程")
                    .font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(20)
            Divider()
            Form {
                Section("基本信息") {
                    Picker("类型", selection: $form.type) {
                        ForEach(EventType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    TextField("标题，例如一面 · 技术面", text: $form.title)
                    if form.type.isInterview {
                        Toggle("记录面试轮次", isOn: $hasRound)
                        if hasRound {
                            Stepper("第 \(form.round ?? 1) 轮", value: Binding(
                                get: { form.round ?? 1 },
                                set: { form.round = $0 }
                            ), in: 1...20)
                        }
                    }
                    Picker("进度结果", selection: $form.result) {
                        ForEach(EventResult.allCases) { result in
                            Text(result.rawValue).tag(result)
                        }
                    }
                }

                Section("时间与地点") {
                    DatePicker("开始时间", selection: $form.startsAt)
                    Toggle("设置结束时间", isOn: $hasEndTime)
                    if hasEndTime {
                        DatePicker("结束时间", selection: Binding(
                            get: { form.endsAt ?? form.startsAt.addingTimeInterval(3_600) },
                            set: { form.endsAt = $0 }
                        ))
                    }
                    Picker("形式", selection: $form.format) {
                        ForEach(InterviewFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    TextField("会议链接", text: $form.meetingURL)
                    TextField("地点", text: $form.location)
                    TextField("面试官或联系人", text: $form.interviewer)
                }

                Section("提醒") {
                    reminderToggle("提前 1 天", minutes: 1_440)
                    reminderToggle("提前 2 小时", minutes: 120)
                    reminderToggle("提前 15 分钟", minutes: 15)
                    ForEach(customReminderMinutes, id: \.self) { minutes in
                        reminderToggle(
                            "提前 \(AppFormatters.reminderLeadTime(minutes))（自定义）",
                            minutes: minutes
                        )
                    }
                    if !store.settings.notificationsEnabled {
                        Label("需要在“设置”中开启系统通知", systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("记录与复盘") {
                    HStack {
                        Text("使用结构化模板快速完成面试复盘")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(InterviewReviewTemplates.all) { template in
                                Button {
                                    form.questions = template.questions
                                    form.review = template.review
                                } label: {
                                    Label(template.name, systemImage: template.icon)
                                }
                            }
                        } label: {
                            Label("套用模板", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    LabeledField("面试问题") {
                        LargeTextEditor(text: $form.questions, minimumHeight: 70)
                    }
                    LabeledField("复盘") {
                        LargeTextEditor(text: $form.review, minimumHeight: 80)
                    }
                    LabeledField("备注") {
                        LargeTextEditor(text: $form.notes, minimumHeight: 60)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: 720)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: hasEndTime) { _, enabled in
            if enabled, form.endsAt == nil { form.endsAt = form.startsAt.addingTimeInterval(3_600) }
            if !enabled { form.endsAt = nil }
        }
        .onChange(of: hasRound) { _, enabled in
            if enabled, form.round == nil { form.round = 1 }
            if !enabled { form.round = nil }
        }
        .onChange(of: form.type) { _, type in
            if type.isInterview {
                if hasRound, form.round == nil { form.round = 1 }
            } else {
                hasRound = false
                form.round = nil
            }
        }
        .onChange(of: form.startsAt) { oldValue, newValue in
            guard let endsAt = form.endsAt, endsAt < newValue else { return }
            let previousDuration = max(0, endsAt.timeIntervalSince(oldValue))
            form.endsAt = newValue.addingTimeInterval(previousDuration)
        }
    }

    private var customReminderMinutes: [Int] {
        form.reminderMinutes
            .filter { ![15, 120, 1_440].contains($0) }
            .sorted(by: >)
    }

    private func reminderToggle(_ title: String, minutes: Int) -> some View {
        Toggle(title, isOn: Binding(
            get: { form.reminderMinutes.contains(minutes) },
            set: { enabled in
                if enabled {
                    if !form.reminderMinutes.contains(minutes) { form.reminderMinutes.append(minutes) }
                } else {
                    form.reminderMinutes.removeAll { $0 == minutes }
                }
            }
        ))
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let event {
            form = store.eventFormData(for: event)
            hasEndTime = form.endsAt != nil
            hasRound = form.round != nil
        }
        didLoad = true
    }

    private func save() {
        store.saveEvent(id: event?.id, applicationID: applicationID, data: form)
        guard store.lastSaveError == nil else { return }
        Task { await ReminderService.refresh(store: store) }
        dismiss()
    }
}

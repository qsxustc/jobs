import SwiftUI

struct TodoEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let fixedApplicationID: UUID?
    let todo: TodoItem?
    @State private var form = TodoFormData()
    @State private var hasDueDate = true
    @State private var hasReminder = true
    @State private var didLoad = false

    init(applicationID: UUID? = nil, todo: TodoItem? = nil) {
        self.fixedApplicationID = applicationID
        self.todo = todo
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(todo == nil ? "新建待办" : "编辑待办")
                    .font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
            Divider()
            Form {
                Section("待办事项") {
                    TextField("要完成什么？", text: $form.title)
                    Picker("优先级", selection: $form.priority) {
                        ForEach(Priority.allCases) { priority in
                            Text(priority.rawValue).tag(priority)
                        }
                    }
                    Picker("关联投递", selection: $form.applicationID) {
                        Text("不关联岗位").tag(nil as UUID?)
                        ForEach(store.activeApplications) { application in
                            Text("\(store.company(for: application)?.name ?? "未知公司") · \(application.position)")
                                .tag(application.id as UUID?)
                        }
                    }
                    .disabled(fixedApplicationID != nil)
                }

                Section("截止与提醒") {
                    Toggle("设置截止时间", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("截止时间", selection: Binding(
                            get: { form.dueAt ?? Date().addingTimeInterval(86_400) },
                            set: { form.dueAt = $0 }
                        ))
                        Toggle("到期前提醒", isOn: $hasReminder)
                        if hasReminder {
                            Picker("提前", selection: Binding(
                                get: { form.reminderMinutes ?? 120 },
                                set: { form.reminderMinutes = $0 }
                            )) {
                                Text("15 分钟").tag(15)
                                Text("2 小时").tag(120)
                                Text("1 天").tag(1_440)
                            }
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $form.notes)
                        .frame(minHeight: 100)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 500)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: hasDueDate) { _, enabled in
            if enabled, form.dueAt == nil { form.dueAt = Date().addingTimeInterval(86_400) }
            if !enabled {
                form.dueAt = nil
                form.reminderMinutes = nil
                hasReminder = false
            }
        }
        .onChange(of: hasReminder) { _, enabled in
            form.reminderMinutes = enabled ? (form.reminderMinutes ?? 120) : nil
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let todo {
            form = store.todoFormData(for: todo)
            hasDueDate = form.dueAt != nil
            hasReminder = form.reminderMinutes != nil
        } else {
            if let fixedApplicationID { form.applicationID = fixedApplicationID }
            let defaultMinutes = store.settings.defaultReminderMinutes
            form.reminderMinutes = defaultMinutes > 0 ? defaultMinutes : nil
            hasReminder = form.reminderMinutes != nil
        }
        didLoad = true
    }

    private func save() {
        if let fixedApplicationID { form.applicationID = fixedApplicationID }
        store.saveTodo(id: todo?.id, data: form)
        guard store.lastSaveError == nil else { return }
        Task { await ReminderService.refresh(store: store) }
        dismiss()
    }
}

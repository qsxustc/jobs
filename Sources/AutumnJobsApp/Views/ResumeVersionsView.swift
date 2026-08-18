import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ResumeVersionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewResume = false
    @State private var editingResume: ResumeVersion?
    @State private var pendingDelete: ResumeVersion?

    var body: some View {
        ScrollView {
            if store.resumeVersions.isEmpty {
                EmptyStateView(icon: "doc.badge.plus", title: "还没有简历版本", message: "创建不同方向的简历，并关联到投递记录以比较效果。")
                    .padding(24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(store.resumeVersions.sorted { lhs, rhs in
                        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                        return lhs.updatedAt > rhs.updatedAt
                    }) { resume in
                        ResumeVersionCard(
                            resume: resume,
                            applicationCount: store.applications.filter { $0.resumeVersionID == resume.id }.count,
                            onEdit: { editingResume = resume },
                            onDelete: { pendingDelete = resume }
                        )
                    }
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("简历版本")
        .toolbar {
            Button {
                showingNewResume = true
            } label: {
                Label("新建简历版本", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showingNewResume) { ResumeEditorView() }
        .sheet(item: $editingResume) { ResumeEditorView(resume: $0) }
        .alert("删除简历版本？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { resume in
            Button("删除", role: .destructive) { store.deleteResumeVersion(id: resume.id) }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("已有投递记录会保留，但将取消与此简历版本的关联。原始简历文件不会被删除。")
        }
    }
}

private struct ResumeVersionCard: View {
    let resume: ResumeVersion
    let applicationCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(resume.name).font(.headline)
                        if resume.isDefault {
                            Text("默认")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.1), in: Capsule())
                        }
                    }
                    Text(resume.target.isEmpty ? "未填写目标方向" : resume.target)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            HStack(spacing: 18) {
                Label("关联 \(applicationCount) 条投递", systemImage: "paperplane")
                Label("更新于 \(AppFormatters.date.string(from: resume.updatedAt))", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !resume.notes.isEmpty {
                Text(resume.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                if !resume.filePath.isEmpty, FileManager.default.fileExists(atPath: resume.filePath) {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: resume.filePath))
                    } label: {
                        Label("打开简历", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label(resume.filePath.isEmpty ? "未关联文件" : "文件已移动", systemImage: "doc.badge.ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("编辑", action: onEdit)
            }
        }
        .padding(17)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.quaternary) }
    }
}

struct ResumeEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let resume: ResumeVersion?
    @State private var form = ResumeFormData()
    @State private var didLoad = false

    init(resume: ResumeVersion? = nil) {
        self.resume = resume
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(resume == nil ? "新建简历版本" : "编辑简历版本")
                    .font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    store.saveResumeVersion(id: resume?.id, data: form)
                    if store.lastSaveError == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
            Divider()
            Form {
                TextField("版本名称，例如后端开发 V3", text: $form.name)
                TextField("目标方向，例如后端研发、产品经理", text: $form.target)
                HStack {
                    TextField("简历文件", text: $form.filePath)
                    Button("选择文件") { chooseFile() }
                }
                Toggle("设为新投递的默认简历", isOn: $form.isDefault)
                LabeledField("版本说明") {
                    LargeTextEditor(text: $form.notes, minimumHeight: 100)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 580, height: 420)
        .onAppear {
            guard !didLoad else { return }
            if let resume { form = store.resumeFormData(for: resume) }
            didLoad = true
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择简历文件"
        panel.allowedContentTypes = [.pdf, .plainText, .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        form.filePath = url.path
        if form.name.isEmpty { form.name = url.deletingPathExtension().lastPathComponent }
    }
}

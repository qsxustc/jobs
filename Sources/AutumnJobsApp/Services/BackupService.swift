import Foundation

struct LocalBackup: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let byteCount: Int

    var id: URL { url }
}

enum BackupService {
    static let maximumRollingBackupCount = 20

    static func encode(_ snapshot: AppSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> AppSnapshot {
        guard data.count <= AppDataLimits.maximumBackupBytes else {
            throw BackupError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppSnapshot.self, from: data)
        return try prepare(snapshot)
    }

    static func prepare(_ source: AppSnapshot) throws -> AppSnapshot {
        var snapshot = source
        guard snapshot.schemaVersion > 0 else {
            throw BackupError.invalidData("数据版本号无效。")
        }
        guard snapshot.schemaVersion <= AppSnapshot.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }

        if snapshot.schemaVersion < 2 {
            if snapshot.tags?.isEmpty != false {
                snapshot.tags = [
                    JobTag(name: "重点关注", colorKey: "orange"),
                    JobTag(name: "需要跟进", colorKey: "red"),
                    JobTag(name: "准备中", colorKey: "blue")
                ]
            }
            if snapshot.resumeVersions?.isEmpty != false {
                snapshot.resumeVersions = [ResumeVersion(name: "通用简历", target: "通用", isDefault: true)]
            }
            snapshot.customStages = snapshot.customStages ?? []
        }
        // Schema v3 adds JobApplication.offerSalary. JobApplication's custom
        // decoder supplies an empty value for older snapshots, so no record
        // transformation is needed here; marking the prepared snapshot current
        // ensures manual restores and subsequent exports use the new schema.
        snapshot.schemaVersion = AppSnapshot.currentSchemaVersion

        try validate(snapshot)
        return snapshot
    }

    static func rollingBackupDirectory(for storageURL: URL) -> URL {
        let storageName = storageURL.deletingPathExtension().lastPathComponent
        return storageURL.deletingLastPathComponent()
            .appendingPathComponent("\(storageName)-backups", isDirectory: true)
    }

    @discardableResult
    static func createRollingBackup(
        _ snapshot: AppSnapshot,
        in directory: URL,
        now: Date = Date(),
        maximumCount: Int = maximumRollingBackupCount
    ) throws -> LocalBackup {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let milliseconds = Int64(now.timeIntervalSince1970 * 1_000)
        let url = directory.appendingPathComponent(
            "autumn-jobs-\(milliseconds)-\(UUID().uuidString.prefix(8)).json"
        )
        let data = try encode(snapshot)
        try data.write(to: url, options: .atomic)

        let backups = localBackups(in: directory)
        for obsolete in backups.dropFirst(max(1, maximumCount)) {
            try? manager.removeItem(at: obsolete.url)
        }
        return LocalBackup(url: url, createdAt: now, byteCount: data.count)
    }

    static func localBackups(in directory: URL) -> [LocalBackup] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return LocalBackup(
                url: url,
                createdAt: values.contentModificationDate ?? .distantPast,
                byteCount: values.fileSize ?? 0
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private static func validate(_ snapshot: AppSnapshot) throws {
        try requireCount(snapshot.companies.count, name: "公司", maximum: AppDataLimits.maximumPrimaryRecords)
        try requireCount(snapshot.projects.count, name: "招聘项目", maximum: AppDataLimits.maximumPrimaryRecords)
        try requireCount(snapshot.applications.count, name: "投递", maximum: AppDataLimits.maximumPrimaryRecords)
        try requireCount(snapshot.events.count, name: "流程事件", maximum: AppDataLimits.maximumRelatedRecords)
        try requireCount(snapshot.todos.count, name: "待办", maximum: AppDataLimits.maximumRelatedRecords)
        try requireCount(snapshot.statusHistory.count, name: "状态历史", maximum: AppDataLimits.maximumRelatedRecords)
        try requireCount(snapshot.customStages?.count ?? 0, name: "自定义状态", maximum: AppDataLimits.maximumPrimaryRecords)
        try requireCount(snapshot.tags?.count ?? 0, name: "标签", maximum: AppDataLimits.maximumPrimaryRecords)
        try requireCount(snapshot.resumeVersions?.count ?? 0, name: "简历版本", maximum: AppDataLimits.maximumPrimaryRecords)

        try requireUniqueIDs(snapshot.companies, name: "公司")
        try requireUniqueIDs(snapshot.projects, name: "招聘项目")
        try requireUniqueIDs(snapshot.applications, name: "投递")
        try requireUniqueIDs(snapshot.events, name: "流程事件")
        try requireUniqueIDs(snapshot.todos, name: "待办")
        try requireUniqueIDs(snapshot.statusHistory, name: "状态历史")
        try requireUniqueIDs(snapshot.customStages ?? [], name: "自定义状态")
        try requireUniqueIDs(snapshot.tags ?? [], name: "标签")
        try requireUniqueIDs(snapshot.resumeVersions ?? [], name: "简历版本")

        let companyIDs = Set(snapshot.companies.map(\.id))
        let projectByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        let applicationIDs = Set(snapshot.applications.map(\.id))
        let stageIDs = Set((snapshot.customStages ?? []).map(\.id))
        let tagIDs = Set((snapshot.tags ?? []).map(\.id))
        let resumeIDs = Set((snapshot.resumeVersions ?? []).map(\.id))

        for project in snapshot.projects where !companyIDs.contains(project.companyID) {
            throw BackupError.invalidData("招聘项目“\(project.name)”引用了不存在的公司。")
        }
        for application in snapshot.applications {
            guard companyIDs.contains(application.companyID) else {
                throw BackupError.invalidData("岗位“\(application.position)”引用了不存在的公司。")
            }
            if let projectID = application.projectID {
                guard let project = projectByID[projectID], project.companyID == application.companyID else {
                    throw BackupError.invalidData("岗位“\(application.position)”关联了无效的招聘项目。")
                }
            }
            if let stageID = application.customStageID, !stageIDs.contains(stageID) {
                throw BackupError.invalidData("岗位“\(application.position)”关联了无效的自定义状态。")
            }
            if !(application.tagIDs ?? []).allSatisfy(tagIDs.contains) {
                throw BackupError.invalidData("岗位“\(application.position)”关联了无效的标签。")
            }
            if let resumeID = application.resumeVersionID, !resumeIDs.contains(resumeID) {
                throw BackupError.invalidData("岗位“\(application.position)”关联了无效的简历版本。")
            }
        }
        for event in snapshot.events {
            guard applicationIDs.contains(event.applicationID) else {
                throw BackupError.invalidData("流程事件“\(event.title)”引用了不存在的投递。")
            }
            if let endsAt = event.endsAt, endsAt < event.startsAt {
                throw BackupError.invalidData("流程事件“\(event.title)”的结束时间早于开始时间。")
            }
            guard event.reminderMinutes.allSatisfy(validReminder) else {
                throw BackupError.invalidData("流程事件“\(event.title)”包含无效的提醒时间。")
            }
        }
        for todo in snapshot.todos {
            if let applicationID = todo.applicationID, !applicationIDs.contains(applicationID) {
                throw BackupError.invalidData("待办“\(todo.title)”引用了不存在的投递。")
            }
            if let reminder = todo.reminderMinutes {
                guard todo.dueAt != nil, validReminder(reminder) else {
                    throw BackupError.invalidData("待办“\(todo.title)”包含无效的提醒时间。")
                }
            }
        }
        for history in snapshot.statusHistory where !applicationIDs.contains(history.applicationID) {
            throw BackupError.invalidData("状态历史引用了不存在的投递。")
        }
        if (snapshot.resumeVersions ?? []).filter(\.isDefault).count > 1 {
            throw BackupError.invalidData("备份中存在多个默认简历版本。")
        }
    }

    private static func validReminder(_ minutes: Int) -> Bool {
        (1...AppDataLimits.maximumReminderMinutes).contains(minutes)
    }

    private static func requireCount(_ count: Int, name: String, maximum: Int) throws {
        guard count <= maximum else {
            throw BackupError.invalidData("\(name)记录超过允许的数量上限。")
        }
    }

    private static func requireUniqueIDs<T: Identifiable>(_ values: [T], name: String) throws where T.ID: Hashable {
        guard Set(values.map(\.id)).count == values.count else {
            throw BackupError.invalidData("\(name)记录中存在重复 ID。")
        }
    }
}

enum BackupError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case fileTooLarge
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "该备份来自更高版本（数据版本 \(version)），请先升级秋招助手。"
        case .fileTooLarge:
            return "备份文件过大，最大支持 100 MB。"
        case .invalidData(let message):
            return "备份数据无效：\(message)"
        }
    }
}

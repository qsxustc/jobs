import Foundation

struct CSVImportResult {
    let importedCount: Int
    let skippedDuplicateCount: Int
}

enum AppStoreError: LocalizedError {
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let message): return message
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var companies: [Company] = []
    @Published private(set) var projects: [RecruitmentProject] = []
    @Published private(set) var applications: [JobApplication] = []
    @Published private(set) var events: [ProcessEvent] = []
    @Published private(set) var todos: [TodoItem] = []
    @Published private(set) var statusHistory: [StatusHistory] = []
    @Published private(set) var customStages: [CustomStage] = []
    @Published private(set) var tags: [JobTag] = []
    @Published private(set) var resumeVersions: [ResumeVersion] = []
    @Published private(set) var settings = UserSettings()
    @Published var lastSaveError: String?
    @Published var lastNotificationError: String?

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastPersistedSnapshot: AppSnapshot?
    private var protectsUnreadableStorage = false

    init(storageURL: URL? = nil, loadSampleIfEmpty: Bool = true) {
        let baseURL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("AutumnJobs", isDirectory: true)
        self.storageURL = storageURL ?? baseURL.appendingPathComponent("job-data.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        lastPersistedSnapshot = currentSnapshot()

        if FileManager.default.fileExists(atPath: self.storageURL.path) {
            _ = load()
        } else if loadSampleIfEmpty {
            seedSampleData()
            seedV2Defaults()
            _ = persist()
        }
    }

    var activeApplications: [JobApplication] {
        applications.filter { !$0.isArchived }
    }

    var upcomingEvents: [ProcessEvent] {
        events
            .filter { event in
                event.startsAt >= Date() && event.result.isPending &&
                application(id: event.applicationID)?.isArchived == false
            }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var openTodos: [TodoItem] {
        todos
            .filter { todo in
                !todo.isCompleted && application(id: todo.applicationID)?.isArchived != true
            }
            .sorted {
                switch ($0.dueAt, $1.dueAt) {
                case let (left?, right?):
                    if left != right { return left < right }
                    return $0.priority.sortValue > $1.priority.sortValue
                case (_?, nil): return true
                case (nil, _?): return false
                default: return $0.priority.sortValue > $1.priority.sortValue
                }
            }
    }

    func company(for application: JobApplication) -> Company? {
        companies.first { $0.id == application.companyID }
    }

    func company(id: UUID) -> Company? {
        companies.first { $0.id == id }
    }

    func customStage(id: UUID?) -> CustomStage? {
        guard let id else { return nil }
        return customStages.first { $0.id == id }
    }

    func tags(for application: JobApplication) -> [JobTag] {
        let ids = Set(application.tagIDs ?? [])
        return tags.filter { ids.contains($0.id) }
    }

    func resumeVersion(for application: JobApplication) -> ResumeVersion? {
        guard let id = application.resumeVersionID else { return nil }
        return resumeVersions.first { $0.id == id }
    }

    func effectiveStatusName(for application: JobApplication) -> String {
        customStage(id: application.customStageID)?.name ?? application.status.rawValue
    }

    func isActive(_ application: JobApplication) -> Bool {
        if let stage = customStage(id: application.customStageID) {
            return !stage.isTerminal
        }
        return application.status.isActive
    }

    func project(for application: JobApplication) -> RecruitmentProject? {
        guard let projectID = application.projectID else { return nil }
        return projects.first { $0.id == projectID }
    }

    func application(id: UUID?) -> JobApplication? {
        guard let id else { return nil }
        return applications.first { $0.id == id }
    }

    func events(for applicationID: UUID) -> [ProcessEvent] {
        events.filter { $0.applicationID == applicationID }.sorted { $0.startsAt < $1.startsAt }
    }

    func todos(for applicationID: UUID) -> [TodoItem] {
        todos.filter { $0.applicationID == applicationID }.sorted {
            ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
        }
    }

    func history(for applicationID: UUID) -> [StatusHistory] {
        statusHistory.filter { $0.applicationID == applicationID }.sorted { $0.changedAt > $1.changedAt }
    }

    func firstResponseDate(for application: JobApplication) -> Date? {
        guard let appliedAt = application.appliedAt else { return nil }
        return statusHistory
            .filter {
                $0.applicationID == application.id &&
                $0.changedAt >= appliedAt &&
                ($0.toCustomName != nil || ![.evaluating, .toApply, .applied].contains($0.toStatus))
            }
            .map(\.changedAt)
            .min()
    }

    func interviewCount(for applicationID: UUID) -> Int {
        events.filter { $0.applicationID == applicationID && $0.type.isInterview && $0.result != .cancelled }.count
    }

    func nextEvent(for applicationID: UUID) -> ProcessEvent? {
        events
            .filter { $0.applicationID == applicationID && $0.startsAt >= Date() && $0.result.isPending }
            .min { $0.startsAt < $1.startsAt }
    }

    func formData(for application: JobApplication) -> ApplicationFormData {
        let company = company(for: application)
        let project = project(for: application)
        return ApplicationFormData(
            companyName: company?.name ?? "",
            companyIndustry: company?.industry ?? "",
            companyNature: company?.nature ?? "",
            companyWebsite: company?.website ?? "",
            recruitmentURL: company?.recruitmentURL ?? "",
            projectName: project?.name ?? "",
            projectType: project?.type ?? "秋招",
            projectURL: project?.url ?? "",
            projectDeadline: project?.deadline,
            position: application.position,
            category: application.category,
            department: application.department,
            location: application.location,
            jdURL: application.jdURL,
            channel: application.channel,
            referrer: application.referrer,
            appliedAt: application.appliedAt,
            status: application.status,
            customStageID: application.customStageID,
            tagIDs: Set(application.tagIDs ?? []),
            resumeVersionID: application.resumeVersionID,
            priority: application.priority,
            salary: application.salary,
            notes: application.notes
        )
    }

    @discardableResult
    func saveApplication(id: UUID? = nil, data: ApplicationFormData) -> UUID {
        let applicationID = upsertApplication(id: id, data: data, updateSharedMetadata: true)
        _ = persist()
        return applicationID
    }

    func importApplications(_ forms: [ApplicationFormData]) throws -> CSVImportResult {
        guard forms.count <= max(0, AppDataLimits.maximumPrimaryRecords - applications.count) else {
            throw CSVError.tooManyRecords
        }
        var importedCount = 0
        var skippedDuplicateCount = 0
        var importKeys = Set(applications.compactMap(importKey))

        for form in forms {
            let key = importKey(form)
            guard importKeys.insert(key).inserted else {
                skippedDuplicateCount += 1
                continue
            }
            var prepared = form
            if !form.importedCustomStageName.isEmpty {
                prepared.customStageID = ensureCustomStage(name: form.importedCustomStageName, colorKey: "indigo", isTerminal: false)
            }
            for name in form.importedTagNames {
                prepared.tagIDs.insert(ensureTag(name: name, colorKey: "blue"))
            }
            if !form.importedResumeName.isEmpty {
                prepared.resumeVersionID = ensureResumeVersion(name: form.importedResumeName)
            }

            _ = upsertApplication(
                id: nil,
                data: prepared,
                updateSharedMetadata: false
            )
            importedCount += 1
        }

        guard persist() else {
            throw AppStoreError.persistenceFailed(lastSaveError ?? "导入数据保存失败。")
        }
        return CSVImportResult(importedCount: importedCount, skippedDuplicateCount: skippedDuplicateCount)
    }

    private func upsertApplication(
        id: UUID?,
        data: ApplicationFormData,
        updateSharedMetadata: Bool
    ) -> UUID {
        let normalizedCompanyName = data.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalApplication = id.flatMap { application(id: $0) }
        let validCustomStageID = data.customStageID.flatMap { customStage(id: $0)?.id }
        let validTagIDs = tags.filter { data.tagIDs.contains($0.id) }.map(\.id)
        let validResumeVersionID = data.resumeVersionID.flatMap { id in
            resumeVersions.contains(where: { $0.id == id }) ? id : nil
        }
        let companyID: UUID
        if let index = companies.firstIndex(where: { $0.name.caseInsensitiveCompare(normalizedCompanyName) == .orderedSame }) {
            if updateSharedMetadata, originalApplication?.companyID == companies[index].id {
                companies[index].industry = data.companyIndustry
                companies[index].nature = data.companyNature
                companies[index].website = data.companyWebsite
                companies[index].recruitmentURL = data.recruitmentURL
            }
            companyID = companies[index].id
        } else {
            let company = Company(
                name: normalizedCompanyName,
                industry: data.companyIndustry,
                nature: data.companyNature,
                website: data.companyWebsite,
                recruitmentURL: data.recruitmentURL
            )
            companies.append(company)
            companyID = company.id
        }

        var projectID: UUID?
        let normalizedProjectName = data.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedProjectName.isEmpty {
            if let index = projects.firstIndex(where: {
                $0.companyID == companyID && $0.name.caseInsensitiveCompare(normalizedProjectName) == .orderedSame
            }) {
                if updateSharedMetadata, originalApplication?.projectID == projects[index].id {
                    projects[index].type = data.projectType
                    projects[index].url = data.projectURL
                    projects[index].deadline = data.projectDeadline
                }
                projectID = projects[index].id
            } else {
                let project = RecruitmentProject(
                    companyID: companyID,
                    name: normalizedProjectName,
                    type: data.projectType,
                    url: data.projectURL,
                    deadline: data.projectDeadline
                )
                projects.append(project)
                projectID = project.id
            }
        }

        let now = Date()
        let applicationID: UUID
        if let id, let index = applications.firstIndex(where: { $0.id == id }) {
            let previousStatus = applications[index].status
            let previousCustomStageID = applications[index].customStageID
            let previousCustomName = customStage(id: previousCustomStageID)?.name
            applications[index].companyID = companyID
            applications[index].projectID = projectID
            applications[index].position = data.position.trimmingCharacters(in: .whitespacesAndNewlines)
            applications[index].category = data.category
            applications[index].department = data.department
            applications[index].location = data.location
            applications[index].jdURL = data.jdURL
            applications[index].channel = data.channel
            applications[index].referrer = data.referrer
            applications[index].appliedAt = data.appliedAt
            applications[index].status = data.status
            applications[index].customStageID = validCustomStageID
            applications[index].tagIDs = validTagIDs
            applications[index].resumeVersionID = validResumeVersionID
            applications[index].priority = data.priority
            applications[index].salary = data.salary
            applications[index].notes = data.notes
            applications[index].updatedAt = now
            applicationID = id
            if previousStatus != data.status || previousCustomStageID != validCustomStageID {
                statusHistory.append(StatusHistory(
                    applicationID: id,
                    fromStatus: previousStatus,
                    toStatus: data.status,
                    fromCustomName: previousCustomName,
                    toCustomName: customStage(id: validCustomStageID)?.name
                ))
            }
        } else {
            let application = JobApplication(
                companyID: companyID,
                projectID: projectID,
                position: data.position.trimmingCharacters(in: .whitespacesAndNewlines),
                category: data.category,
                department: data.department,
                location: data.location,
                jdURL: data.jdURL,
                channel: data.channel,
                referrer: data.referrer,
                appliedAt: data.appliedAt,
                status: data.status,
                customStageID: validCustomStageID,
                tagIDs: validTagIDs,
                resumeVersionID: validResumeVersionID,
                priority: data.priority,
                salary: data.salary,
                notes: data.notes,
                updatedAt: now
            )
            applications.append(application)
            statusHistory.append(StatusHistory(
                applicationID: application.id,
                fromStatus: nil,
                toStatus: data.status,
                toCustomName: customStage(id: validCustomStageID)?.name
            ))
            applicationID = application.id
        }
        return applicationID
    }

    func updateStatus(applicationID: UUID, to status: ApplicationStatus) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let oldStatus = applications[index].status
        let previousCustomName = customStage(id: applications[index].customStageID)?.name
        guard oldStatus != status || applications[index].customStageID != nil else { return }
        applications[index].status = status
        applications[index].customStageID = nil
        applications[index].updatedAt = Date()
        statusHistory.append(StatusHistory(
            applicationID: applicationID,
            fromStatus: oldStatus,
            toStatus: status,
            fromCustomName: previousCustomName
        ))
        _ = persist()
    }

    func updateCustomStage(applicationID: UUID, customStageID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }),
              let destination = customStage(id: customStageID) else { return }
        let previousStatus = applications[index].status
        let previousCustomName = customStage(id: applications[index].customStageID)?.name
        guard applications[index].customStageID != customStageID else { return }
        applications[index].customStageID = customStageID
        applications[index].updatedAt = Date()
        statusHistory.append(StatusHistory(
            applicationID: applicationID,
            fromStatus: previousStatus,
            toStatus: previousStatus,
            fromCustomName: previousCustomName,
            toCustomName: destination.name
        ))
        _ = persist()
    }

    func deleteApplication(id: UUID) {
        applications.removeAll { $0.id == id }
        events.removeAll { $0.applicationID == id }
        todos.removeAll { $0.applicationID == id }
        statusHistory.removeAll { $0.applicationID == id }
        _ = persist()
    }

    func archiveApplication(id: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        applications[index].isArchived.toggle()
        applications[index].updatedAt = Date()
        _ = persist()
    }

    func touchApplication(id: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        applications[index].updatedAt = Date()
        _ = persist()
    }

    @discardableResult
    func saveEvent(id: UUID? = nil, applicationID: UUID, data: EventFormData) -> UUID {
        let normalizedTitle = data.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = data.endsAt.map { max($0, data.startsAt) }
        let normalizedReminders = Array(Set(data.reminderMinutes.filter {
            (1...AppDataLimits.maximumReminderMinutes).contains($0)
        })).sorted(by: >)
        let eventID: UUID
        if let id, let index = events.firstIndex(where: { $0.id == id }) {
            events[index].applicationID = applicationID
            events[index].type = data.type
            events[index].title = normalizedTitle
            events[index].round = data.type.isInterview ? data.round : nil
            events[index].startsAt = data.startsAt
            events[index].endsAt = normalizedEnd
            events[index].format = data.format
            events[index].meetingURL = data.meetingURL
            events[index].location = data.location
            events[index].interviewer = data.interviewer
            events[index].result = data.result
            events[index].questions = data.questions
            events[index].review = data.review
            events[index].notes = data.notes
            events[index].reminderMinutes = normalizedReminders
            events[index].updatedAt = Date()
            eventID = id
        } else {
            let event = ProcessEvent(
                applicationID: applicationID,
                type: data.type,
                title: normalizedTitle,
                round: data.type.isInterview ? data.round : nil,
                startsAt: data.startsAt,
                endsAt: normalizedEnd,
                format: data.format,
                meetingURL: data.meetingURL,
                location: data.location,
                interviewer: data.interviewer,
                result: data.result,
                questions: data.questions,
                review: data.review,
                notes: data.notes,
                reminderMinutes: normalizedReminders
            )
            events.append(event)
            eventID = event.id
        }
        if data.type.isInterview, data.result.isPending,
           let appIndex = applications.firstIndex(where: { $0.id == applicationID }),
           applications[appIndex].customStageID == nil,
           applications[appIndex].status.isActive,
           applications[appIndex].status.sortOrder < ApplicationStatus.interviewing.sortOrder {
            let old = applications[appIndex].status
            applications[appIndex].status = .interviewing
            applications[appIndex].updatedAt = Date()
            statusHistory.append(StatusHistory(applicationID: applicationID, fromStatus: old, toStatus: .interviewing, note: "添加面试安排"))
        }
        _ = persist()
        return eventID
    }

    func eventFormData(for event: ProcessEvent) -> EventFormData {
        EventFormData(
            type: event.type,
            title: event.title,
            round: event.round,
            startsAt: event.startsAt,
            endsAt: event.endsAt,
            format: event.format,
            meetingURL: event.meetingURL,
            location: event.location,
            interviewer: event.interviewer,
            result: event.result,
            questions: event.questions,
            review: event.review,
            notes: event.notes,
            reminderMinutes: event.reminderMinutes
        )
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        _ = persist()
    }

    @discardableResult
    func saveTodo(id: UUID? = nil, data: TodoFormData) -> UUID {
        let normalizedTitle = data.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let validApplicationID = data.applicationID.flatMap { application(id: $0)?.id }
        let validReminder = data.dueAt == nil ? nil : data.reminderMinutes.flatMap {
            (1...AppDataLimits.maximumReminderMinutes).contains($0) ? $0 : nil
        }
        if let id, let index = todos.firstIndex(where: { $0.id == id }) {
            todos[index].applicationID = validApplicationID
            todos[index].title = normalizedTitle
            todos[index].dueAt = data.dueAt
            todos[index].priority = data.priority
            todos[index].notes = data.notes
            todos[index].reminderMinutes = validReminder
            _ = persist()
            return id
        }
        let todo = TodoItem(
            applicationID: validApplicationID,
            title: normalizedTitle,
            dueAt: data.dueAt,
            priority: data.priority,
            notes: data.notes,
            reminderMinutes: validReminder
        )
        todos.append(todo)
        _ = persist()
        return todo.id
    }

    func todoFormData(for todo: TodoItem) -> TodoFormData {
        TodoFormData(
            applicationID: todo.applicationID,
            title: todo.title,
            dueAt: todo.dueAt,
            priority: todo.priority,
            notes: todo.notes,
            reminderMinutes: todo.reminderMinutes
        )
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        todos[index].completedAt = todos[index].isCompleted ? Date() : nil
        _ = persist()
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
        _ = persist()
    }

    func updateSettings(_ newSettings: UserSettings) {
        settings = sanitizedSettings(newSettings)
        _ = persist()
    }

    @discardableResult
    func addCustomStage(name: String, colorKey: String, isTerminal: Bool) -> UUID {
        let id = ensureCustomStage(name: name, colorKey: colorKey, isTerminal: isTerminal)
        _ = persist()
        return id
    }

    func deleteCustomStage(id: UUID) {
        customStages.removeAll { $0.id == id }
        for index in applications.indices where applications[index].customStageID == id {
            applications[index].customStageID = nil
            applications[index].updatedAt = Date()
        }
        _ = persist()
    }

    @discardableResult
    func addTag(name: String, colorKey: String) -> UUID {
        let id = ensureTag(name: name, colorKey: colorKey)
        _ = persist()
        return id
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
        for index in applications.indices {
            applications[index].tagIDs?.removeAll { $0 == id }
        }
        _ = persist()
    }

    @discardableResult
    func saveResumeVersion(id: UUID? = nil, data: ResumeFormData) -> UUID {
        if data.isDefault {
            for index in resumeVersions.indices { resumeVersions[index].isDefault = false }
        }
        if let id, let index = resumeVersions.firstIndex(where: { $0.id == id }) {
            resumeVersions[index].name = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
            resumeVersions[index].target = data.target
            resumeVersions[index].filePath = data.filePath
            resumeVersions[index].notes = data.notes
            resumeVersions[index].isDefault = data.isDefault
            resumeVersions[index].updatedAt = Date()
            _ = persist()
            return id
        }
        let resume = ResumeVersion(
            name: data.name.trimmingCharacters(in: .whitespacesAndNewlines),
            target: data.target,
            filePath: data.filePath,
            notes: data.notes,
            isDefault: data.isDefault
        )
        resumeVersions.append(resume)
        _ = persist()
        return resume.id
    }

    func resumeFormData(for resume: ResumeVersion) -> ResumeFormData {
        ResumeFormData(name: resume.name, target: resume.target, filePath: resume.filePath, notes: resume.notes, isDefault: resume.isDefault)
    }

    func deleteResumeVersion(id: UUID) {
        resumeVersions.removeAll { $0.id == id }
        for index in applications.indices where applications[index].resumeVersionID == id {
            applications[index].resumeVersionID = nil
        }
        _ = persist()
    }

    func replace(with snapshot: AppSnapshot) throws {
        let prepared = try BackupService.prepare(snapshot)
        apply(prepared)
        guard persist(allowReplacingUnreadableStorage: true) else {
            throw AppStoreError.persistenceFailed(lastSaveError ?? "恢复后的数据无法保存。")
        }
    }

    func currentSnapshot() -> AppSnapshot {
        AppSnapshot(
            companies: companies,
            projects: projects,
            applications: applications,
            events: events,
            todos: todos,
            statusHistory: statusHistory,
            settings: settings,
            customStages: customStages,
            tags: tags,
            resumeVersions: resumeVersions
        )
    }

    private func load() -> Bool {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return false }
        do {
            let values = try storageURL.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize, fileSize > AppDataLimits.maximumBackupBytes {
                throw BackupError.fileTooLarge
            }
            let data = try Data(contentsOf: storageURL, options: .mappedIfSafe)
            let decoded = try decoder.decode(AppSnapshot.self, from: data)
            let originalSchemaVersion = decoded.schemaVersion
            let snapshot = try BackupService.prepare(decoded)
            if originalSchemaVersion < AppSnapshot.currentSchemaVersion {
                let migrationBackupURL = storageURL.deletingLastPathComponent().appendingPathComponent("job-data-v1-backup.json")
                if !FileManager.default.fileExists(atPath: migrationBackupURL.path) {
                    try FileManager.default.copyItem(at: storageURL, to: migrationBackupURL)
                }
                apply(snapshot)
                guard persist() else { return false }
            } else {
                apply(snapshot)
                lastPersistedSnapshot = currentSnapshot()
                lastSaveError = nil
            }
            return true
        } catch {
            protectsUnreadableStorage = true
            lastSaveError = "读取本地数据失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func persist(allowReplacingUnreadableStorage: Bool = false) -> Bool {
        let candidate = currentSnapshot()
        guard !protectsUnreadableStorage || allowReplacingUnreadableStorage else {
            if let lastPersistedSnapshot { apply(lastPersistedSnapshot) }
            lastSaveError = "本地数据文件无法读取，为避免覆盖原文件，本次修改未保存。请先恢复一份有效备份。"
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(candidate).write(to: storageURL, options: .atomic)
            protectsUnreadableStorage = false
            lastPersistedSnapshot = candidate
            lastSaveError = nil
            return true
        } catch {
            if let lastPersistedSnapshot {
                apply(lastPersistedSnapshot)
            }
            lastSaveError = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func apply(_ snapshot: AppSnapshot) {
        companies = snapshot.companies
        projects = snapshot.projects
        applications = snapshot.applications
        events = snapshot.events
        todos = snapshot.todos
        statusHistory = snapshot.statusHistory
        settings = sanitizedSettings(snapshot.settings)
        customStages = snapshot.customStages ?? []
        tags = snapshot.tags ?? []
        resumeVersions = snapshot.resumeVersions ?? []
    }

    private func sanitizedSettings(_ value: UserSettings) -> UserSettings {
        var result = value
        result.staleDays = min(max(result.staleDays, 1), 365)
        result.defaultReminderMinutes = min(
            max(result.defaultReminderMinutes, 0),
            AppDataLimits.maximumReminderMinutes
        )
        return result
    }

    private func ensureCustomStage(name: String, colorKey: String, isTerminal: Bool) -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = customStages.first(where: {
            $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }) {
            return existing.id
        }
        let stage = CustomStage(
            name: normalizedName,
            colorKey: colorKey,
            order: customStages.count,
            isTerminal: isTerminal
        )
        customStages.append(stage)
        return stage.id
    }

    private func ensureTag(name: String, colorKey: String) -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = tags.first(where: {
            $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }) {
            return existing.id
        }
        let tag = JobTag(name: normalizedName, colorKey: colorKey)
        tags.append(tag)
        return tag.id
    }

    private func ensureResumeVersion(name: String) -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = resumeVersions.first(where: {
            $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }) {
            return existing.id
        }
        let resume = ResumeVersion(name: normalizedName)
        resumeVersions.append(resume)
        return resume.id
    }

    private struct ImportKey: Hashable {
        let company: String
        let project: String
        let position: String
        let appliedAtSecond: Int64?
    }

    private func importKey(_ form: ApplicationFormData) -> ImportKey {
        ImportKey(
            company: normalizedImportText(form.companyName),
            project: normalizedImportText(form.projectName),
            position: normalizedImportText(form.position),
            appliedAtSecond: form.appliedAt.map { Int64($0.timeIntervalSince1970.rounded()) }
        )
    }

    private func importKey(_ application: JobApplication) -> ImportKey? {
        guard let company = company(for: application) else { return nil }
        return ImportKey(
            company: normalizedImportText(company.name),
            project: normalizedImportText(project(for: application)?.name ?? ""),
            position: normalizedImportText(application.position),
            appliedAtSecond: application.appliedAt.map { Int64($0.timeIntervalSince1970.rounded()) }
        )
    }

    private func normalizedImportText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func seedSampleData() {
        let calendar = Calendar.current
        let now = Date()
        let byteDance = Company(name: "字节跳动", industry: "互联网", nature: "民企", website: "https://www.bytedance.com", recruitmentURL: "https://jobs.bytedance.com/campus")
        let tencent = Company(name: "腾讯", industry: "互联网", nature: "民企", website: "https://www.tencent.com", recruitmentURL: "https://join.qq.com")
        let bank = Company(name: "示例银行", industry: "金融", nature: "国企")
        companies = [byteDance, tencent, bank]

        let autumn = RecruitmentProject(companyID: byteDance.id, name: "2027 届秋季校园招聘", url: byteDance.recruitmentURL, deadline: calendar.date(byAdding: .day, value: 25, to: now))
        let early = RecruitmentProject(companyID: tencent.id, name: "2027 届提前批", type: "提前批", url: tencent.recruitmentURL, deadline: calendar.date(byAdding: .day, value: 12, to: now))
        let bankAutumn = RecruitmentProject(companyID: bank.id, name: "总行科技岗秋招", deadline: calendar.date(byAdding: .day, value: 40, to: now))
        projects = [autumn, early, bankAutumn]

        let first = JobApplication(companyID: byteDance.id, projectID: autumn.id, position: "后端开发工程师", category: "研发", department: "商业化技术", location: "上海", jdURL: "https://jobs.bytedance.com/campus", channel: "官网", appliedAt: calendar.date(byAdding: .day, value: -6, to: now), status: .interviewing, priority: .high, notes: "重点准备：系统设计、数据库与项目经历。", updatedAt: now)
        let second = JobApplication(companyID: tencent.id, projectID: early.id, position: "产品经理", category: "产品", department: "互动娱乐", location: "深圳", jdURL: "https://join.qq.com", channel: "内推", referrer: "学长内推", appliedAt: calendar.date(byAdding: .day, value: -3, to: now), status: .screening, priority: .high, updatedAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now)
        let third = JobApplication(companyID: bank.id, projectID: bankAutumn.id, position: "金融科技管培生", category: "管培生", location: "北京", channel: "官网", status: .toApply, priority: .medium, notes: "先根据 JD 调整金融方向简历。", updatedAt: now)
        applications = [first, second, third]

        let interviewDate = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        events = [
            ProcessEvent(applicationID: first.id, type: .interview, title: "一面 · 技术面", round: 1, startsAt: interviewDate, endsAt: calendar.date(byAdding: .minute, value: 60, to: interviewDate), format: .online, meetingURL: "https://meeting.example.com/demo", interviewer: "业务技术面试官")
        ]
        todos = [
            TodoItem(applicationID: first.id, title: "准备一面项目介绍与系统设计", dueAt: calendar.date(byAdding: .day, value: 1, to: now), priority: .high),
            TodoItem(applicationID: third.id, title: "完成金融科技岗定制简历", dueAt: calendar.date(byAdding: .day, value: 3, to: now), priority: .medium),
            TodoItem(title: "整理本周投递复盘", dueAt: calendar.date(byAdding: .day, value: 5, to: now), priority: .low)
        ]
        statusHistory = [
            StatusHistory(applicationID: first.id, fromStatus: nil, toStatus: .applied, changedAt: calendar.date(byAdding: .day, value: -6, to: now) ?? now),
            StatusHistory(applicationID: first.id, fromStatus: .applied, toStatus: .interviewing, changedAt: now),
            StatusHistory(applicationID: second.id, fromStatus: nil, toStatus: .screening, changedAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now),
            StatusHistory(applicationID: third.id, fromStatus: nil, toStatus: .toApply, changedAt: now)
        ]
    }

    private func seedV2Defaults() {
        if tags.isEmpty {
            tags = [
                JobTag(name: "重点关注", colorKey: "orange"),
                JobTag(name: "需要跟进", colorKey: "red"),
                JobTag(name: "准备中", colorKey: "blue")
            ]
        }
        if resumeVersions.isEmpty {
            resumeVersions = [ResumeVersion(name: "通用简历", target: "通用", isDefault: true)]
        }
    }
}

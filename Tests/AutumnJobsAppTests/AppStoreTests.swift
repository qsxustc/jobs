import XCTest
@testable import AutumnJobsApp

@MainActor
final class AppStoreTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AutumnJobsTests-\(UUID().uuidString)")
            .appendingPathComponent("data.json")
    }

    func testApplicationEventTodoAndPersistence() throws {
        let url = temporaryURL()
        let store = AppStore(storageURL: url, loadSampleIfEmpty: false)

        var applicationForm = ApplicationFormData()
        applicationForm.companyName = "测试科技"
        applicationForm.projectName = "2027 秋招"
        applicationForm.position = "macOS 开发工程师"
        applicationForm.status = .applied
        applicationForm.appliedAt = Date()
        let applicationID = store.saveApplication(data: applicationForm)

        XCTAssertEqual(store.companies.count, 1)
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.applications.count, 1)
        XCTAssertEqual(store.history(for: applicationID).count, 1)

        var eventForm = EventFormData()
        eventForm.title = "一面"
        eventForm.round = 1
        store.saveEvent(applicationID: applicationID, data: eventForm)
        XCTAssertEqual(store.events(for: applicationID).count, 1)
        XCTAssertEqual(store.application(id: applicationID)?.status, .interviewing)

        var todoForm = TodoFormData()
        todoForm.applicationID = applicationID
        todoForm.title = "准备项目介绍"
        let todoID = store.saveTodo(data: todoForm)
        store.toggleTodo(id: todoID)
        XCTAssertTrue(store.todos.first?.isCompleted == true)

        let reloaded = AppStore(storageURL: url, loadSampleIfEmpty: false)
        XCTAssertEqual(reloaded.applications.count, 1)
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.todos.count, 1)
        XCTAssertEqual(reloaded.company(for: reloaded.applications[0])?.name, "测试科技")
    }

    func testStatusHistoryOnlyChangesForNewStatus() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var form = ApplicationFormData()
        form.companyName = "状态测试公司"
        form.position = "产品经理"
        form.status = .applied
        let id = store.saveApplication(data: form)

        store.updateStatus(applicationID: id, to: .applied)
        XCTAssertEqual(store.history(for: id).count, 1)

        store.updateStatus(applicationID: id, to: .screening)
        XCTAssertEqual(store.history(for: id).count, 2)
        XCTAssertEqual(store.history(for: id).first?.fromStatus, .applied)
        XCTAssertEqual(store.history(for: id).first?.toStatus, .screening)
    }

    func testCSVDecodingHandlesQuotedFields() throws {
        let csv = "公司,招聘项目,岗位,当前状态,优先级,备注\r\n测试公司,秋招,研发工程师,已投递,高,\"包含,逗号的备注\""
        let forms = try CSVService.decode(Data(csv.utf8))

        XCTAssertEqual(forms.count, 1)
        guard let first = forms.first else { return }
        XCTAssertEqual(first.companyName, "测试公司")
        XCTAssertEqual(first.status, .applied)
        XCTAssertEqual(first.priority, .high)
        XCTAssertEqual(first.notes, "包含,逗号的备注")
    }

    func testBackupRoundTrip() throws {
        let snapshot = AppSnapshot(
            companies: [Company(name: "备份公司")],
            projects: [],
            applications: [],
            events: [],
            todos: [],
            statusHistory: [],
            settings: UserSettings(staleDays: 10)
        )
        let restored = try BackupService.decode(BackupService.encode(snapshot))
        XCTAssertEqual(restored.companies.first?.name, "备份公司")
        XCTAssertEqual(restored.settings.staleDays, 10)
    }

    func testBackgroundIdleSettingIsBackwardCompatibleAndSanitized() throws {
        let legacyData = Data(#"{"notificationsEnabled":true,"staleDays":10,"defaultReminderMinutes":120}"#.utf8)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: legacyData)
        XCTAssertEqual(decoded.backgroundIdleMinutes, 15)

        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        store.updateSettings(UserSettings(backgroundIdleMinutes: 999))
        XCTAssertEqual(store.settings.backgroundIdleMinutes, 15)

        store.updateSettings(UserSettings(backgroundIdleMinutes: 0))
        XCTAssertEqual(store.settings.backgroundIdleMinutes, 0)
    }

    func testBackgroundIdleExitRechecksVisibleWindowsAfterDelay() async {
        let recheckedVisibility = expectation(description: "退出前重新检查窗口")
        var visibilityCheckCount = 0
        var didTerminate = false
        let service = BackgroundIdleService(
            hasVisibleWindows: {
                visibilityCheckCount += 1
                if visibilityCheckCount == 2 {
                    recheckedVisibility.fulfill()
                    return true
                }
                return false
            },
            sleep: { _ in },
            terminate: { didTerminate = true }
        )
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        service.attach(store: store)

        service.scheduleIdleExitIfNeeded()
        await fulfillment(of: [recheckedVisibility], timeout: 1)

        XCTAssertEqual(visibilityCheckCount, 2)
        XCTAssertFalse(didTerminate)
    }

    func testBackgroundIdleExitTerminatesWhenWindowsRemainClosed() async {
        let terminated = expectation(description: "后台闲置后退出")
        let service = BackgroundIdleService(
            hasVisibleWindows: { false },
            sleep: { _ in },
            terminate: { terminated.fulfill() }
        )
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        service.attach(store: store)

        service.scheduleIdleExitIfNeeded()
        await fulfillment(of: [terminated], timeout: 1)
    }

    func testVersionOneSnapshotMigratesWithoutLosingApplications() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let company = Company(name: "旧版数据公司")
        let application = JobApplication(companyID: company.id, position: "旧版岗位", status: .applied)
        let oldSnapshot = AppSnapshot(
            schemaVersion: 1,
            companies: [company],
            projects: [],
            applications: [application],
            events: [],
            todos: [],
            statusHistory: [],
            settings: UserSettings(),
            customStages: nil,
            tags: nil,
            resumeVersions: nil
        )
        try BackupService.encode(oldSnapshot).write(to: url)

        let migrated = AppStore(storageURL: url, loadSampleIfEmpty: false)
        XCTAssertEqual(migrated.applications.first?.position, "旧版岗位")
        XCTAssertFalse(migrated.tags.isEmpty)
        XCTAssertEqual(migrated.resumeVersions.first?.isDefault, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("job-data-v1-backup.json").path))

        let savedSnapshot = try BackupService.decode(Data(contentsOf: url))
        XCTAssertEqual(savedSnapshot.schemaVersion, 2)
    }

    func testCustomStageTagsAndResumeAssociations() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        let stageID = store.addCustomStage(name: "等待 HC", colorKey: "orange", isTerminal: false)
        let tagID = store.addTag(name: "重点", colorKey: "red")
        let resumeID = store.saveResumeVersion(data: ResumeFormData(name: "后端简历 V2", target: "后端"))

        var form = ApplicationFormData()
        form.companyName = "关联测试公司"
        form.position = "后端工程师"
        form.customStageID = stageID
        form.tagIDs = [tagID]
        form.resumeVersionID = resumeID
        let applicationID = store.saveApplication(data: form)
        let application = store.application(id: applicationID)!

        XCTAssertEqual(store.effectiveStatusName(for: application), "等待 HC")
        XCTAssertEqual(store.tags(for: application).first?.name, "重点")
        XCTAssertEqual(store.resumeVersion(for: application)?.name, "后端简历 V2")

        store.updateStatus(applicationID: applicationID, to: .offer)
        XCTAssertNil(store.application(id: applicationID)?.customStageID)
        XCTAssertEqual(store.history(for: applicationID).first?.fromCustomName, "等待 HC")

        store.deleteTag(id: tagID)
        store.deleteResumeVersion(id: resumeID)
        XCTAssertTrue(store.application(id: applicationID)?.tagIDs?.isEmpty == true)
        XCTAssertNil(store.application(id: applicationID)?.resumeVersionID)
    }

    func testSmartAlertsFindOverdueTodoAndMissingReview() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var applicationForm = ApplicationFormData()
        applicationForm.companyName = "提醒测试公司"
        applicationForm.position = "客户端工程师"
        let applicationID = store.saveApplication(data: applicationForm)

        var todo = TodoFormData()
        todo.applicationID = applicationID
        todo.title = "逾期准备事项"
        todo.dueAt = Date().addingTimeInterval(-3_600)
        store.saveTodo(data: todo)

        var event = EventFormData()
        event.type = .interview
        event.title = "一面"
        event.startsAt = Date().addingTimeInterval(-7_200)
        event.result = .completed
        event.review = ""
        store.saveEvent(applicationID: applicationID, data: event)

        let alerts = SmartAlertService.items(store: store)
        XCTAssertTrue(alerts.contains { $0.kind == .overdueTodo })
        XCTAssertTrue(alerts.contains { $0.kind == .missingReview })
    }

    func testUpcomingEventsExcludeFinishedCancelledAndArchivedItems() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var applicationForm = ApplicationFormData()
        applicationForm.companyName = "日程测试公司"
        applicationForm.position = "工程师"
        let applicationID = store.saveApplication(data: applicationForm)

        for result in [EventResult.scheduled, .pending, .completed, .passed, .failed, .cancelled] {
            var event = EventFormData()
            event.title = result.rawValue
            event.startsAt = Date().addingTimeInterval(86_400)
            event.result = result
            store.saveEvent(applicationID: applicationID, data: event)
        }

        XCTAssertEqual(Set(store.upcomingEvents.map(\.result)), [.scheduled, .pending])
        store.archiveApplication(id: applicationID)
        XCTAssertTrue(store.upcomingEvents.isEmpty)
    }

    func testEditingEventNormalizesValuesAndMovesAssociation() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var first = ApplicationFormData()
        first.companyName = "甲公司"
        first.position = "甲岗位"
        let firstID = store.saveApplication(data: first)
        var second = ApplicationFormData()
        second.companyName = "乙公司"
        second.position = "乙岗位"
        let secondID = store.saveApplication(data: second)

        var event = EventFormData()
        event.title = "  一面  "
        event.startsAt = Date().addingTimeInterval(7_200)
        event.endsAt = event.startsAt.addingTimeInterval(-3_600)
        event.reminderMinutes = [120, 120, -1, 15]
        let eventID = store.saveEvent(applicationID: firstID, data: event)
        store.saveEvent(id: eventID, applicationID: secondID, data: event)

        let saved = store.events.first { $0.id == eventID }
        XCTAssertEqual(saved?.applicationID, secondID)
        XCTAssertEqual(saved?.title, "一面")
        XCTAssertEqual(saved?.endsAt, event.startsAt)
        XCTAssertEqual(saved?.reminderMinutes, [120, 15])
        XCTAssertTrue(store.events(for: firstID).isEmpty)
    }

    func testScheduledInterviewKeepsCustomStage() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        let stageID = store.addCustomStage(name: "等待安排", colorKey: "orange", isTerminal: false)
        var application = ApplicationFormData()
        application.companyName = "自定义流程公司"
        application.position = "研发"
        application.customStageID = stageID
        let applicationID = store.saveApplication(data: application)

        var event = EventFormData()
        event.startsAt = Date().addingTimeInterval(86_400)
        store.saveEvent(applicationID: applicationID, data: event)

        XCTAssertEqual(store.application(id: applicationID)?.customStageID, stageID)
    }

    func testTodoAndReferenceInputsAreSanitized() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var todo = TodoFormData()
        todo.applicationID = UUID()
        todo.title = "  整理材料  "
        todo.dueAt = nil
        todo.reminderMinutes = 120
        let todoID = store.saveTodo(data: todo)

        let savedTodo = store.todos.first { $0.id == todoID }
        XCTAssertEqual(savedTodo?.title, "整理材料")
        XCTAssertNil(savedTodo?.applicationID)
        XCTAssertNil(savedTodo?.reminderMinutes)

        var application = ApplicationFormData()
        application.companyName = "引用测试公司"
        application.position = "岗位"
        application.customStageID = UUID()
        application.tagIDs = [UUID()]
        application.resumeVersionID = UUID()
        let applicationID = store.saveApplication(data: application)
        XCTAssertNil(store.application(id: applicationID)?.customStageID)
        XCTAssertTrue(store.application(id: applicationID)?.tagIDs?.isEmpty == true)
        XCTAssertNil(store.application(id: applicationID)?.resumeVersionID)
    }

    func testDuplicateLabelsAndDuplicateCSVHeadersAreHandled() throws {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        let firstStageID = store.addCustomStage(name: "等待 HC", colorKey: "orange", isTerminal: false)
        let duplicateStageID = store.addCustomStage(name: "  等待 hc  ", colorKey: "red", isTerminal: true)
        let firstTagID = store.addTag(name: "重点", colorKey: "red")
        let duplicateTagID = store.addTag(name: "  重点  ", colorKey: "blue")
        XCTAssertEqual(firstStageID, duplicateStageID)
        XCTAssertEqual(firstTagID, duplicateTagID)
        XCTAssertEqual(store.customStages.count, 1)
        XCTAssertEqual(store.tags.count, 1)

        let csv = "公司,公司,岗位\n第一列公司,第二列公司,研发"
        let decoded = try CSVService.decode(Data(csv.utf8))
        XCTAssertEqual(decoded.first?.companyName, "第一列公司")
        XCTAssertEqual(decoded.first?.position, "研发")
    }

    func testMalformedCSVAndFutureBackupAreRejected() throws {
        let malformedCSV = "公司,岗位\n测试公司,\"未闭合岗位"
        XCTAssertThrowsError(try CSVService.decode(Data(malformedCSV.utf8))) { error in
            guard let csvError = error as? CSVError else {
                return XCTFail("Unexpected error: \(error)")
            }
            guard case .malformedCSV = csvError else {
                return XCTFail("Unexpected CSV error: \(csvError)")
            }
        }

        let snapshot = AppSnapshot(
            schemaVersion: AppSnapshot.currentSchemaVersion + 1,
            companies: [],
            projects: [],
            applications: [],
            events: [],
            todos: [],
            statusHistory: [],
            settings: UserSettings()
        )
        XCTAssertThrowsError(try BackupService.decode(BackupService.encode(snapshot)))
    }

    func testArchivingApplicationSuppressesOperationalTodosAndAlerts() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var application = ApplicationFormData()
        application.companyName = "归档测试公司"
        application.projectName = "即将截止项目"
        application.projectDeadline = Date().addingTimeInterval(86_400)
        application.position = "研发"
        let applicationID = store.saveApplication(data: application)

        var todo = TodoFormData()
        todo.applicationID = applicationID
        todo.title = "已归档岗位待办"
        todo.dueAt = Date().addingTimeInterval(-3_600)
        store.saveTodo(data: todo)
        XCTAssertEqual(store.openTodos.count, 1)
        XCTAssertFalse(SmartAlertService.items(store: store).isEmpty)

        store.archiveApplication(id: applicationID)
        XCTAssertTrue(store.openTodos.isEmpty)
        XCTAssertTrue(SmartAlertService.items(store: store).isEmpty)
    }

    func testTerminalApplicationDoesNotTriggerProjectDeadlineAlert() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var application = ApplicationFormData()
        application.companyName = "终态测试公司"
        application.projectName = "即将截止项目"
        application.projectDeadline = Date().addingTimeInterval(86_400)
        application.position = "研发"
        application.status = .rejected
        store.saveApplication(data: application)

        XCTAssertFalse(SmartAlertService.items(store: store).contains { $0.kind == .projectDeadline })
    }

    func testCSVBatchImportPreservesSharedMetadataAndSkipsDuplicates() throws {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        let deadline = Date().addingTimeInterval(86_400)
        var original = ApplicationFormData()
        original.companyName = "元数据公司"
        original.companyIndustry = "互联网"
        original.companyNature = "民企"
        original.companyWebsite = "https://company.example"
        original.recruitmentURL = "https://jobs.example"
        original.projectName = "2027 秋招"
        original.projectType = "提前批"
        original.projectURL = "https://jobs.example/campus"
        original.projectDeadline = deadline
        original.position = "后端工程师"
        store.saveApplication(data: original)

        var imported = ApplicationFormData()
        imported.companyName = original.companyName
        imported.projectName = original.projectName
        imported.position = "客户端工程师"
        let firstResult = try store.importApplications([imported])
        let secondResult = try store.importApplications([imported])

        XCTAssertEqual(firstResult.importedCount, 1)
        XCTAssertEqual(secondResult.importedCount, 0)
        XCTAssertEqual(secondResult.skippedDuplicateCount, 1)
        XCTAssertEqual(store.applications.count, 2)
        XCTAssertEqual(store.companies.first?.industry, "互联网")
        XCTAssertEqual(store.companies.first?.nature, "民企")
        XCTAssertEqual(store.companies.first?.website, "https://company.example")
        XCTAssertEqual(store.companies.first?.recruitmentURL, "https://jobs.example")
        XCTAssertEqual(store.projects.first?.type, "提前批")
        XCTAssertEqual(store.projects.first?.url, "https://jobs.example/campus")
        XCTAssertEqual(store.projects.first?.deadline, deadline)
    }

    func testMovingApplicationToExistingCompanyDoesNotOverwriteTargetMetadata() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var source = ApplicationFormData()
        source.companyName = "甲公司"
        source.companyIndustry = "制造业"
        source.companyWebsite = "https://a.example"
        source.position = "甲岗位"
        let sourceID = store.saveApplication(data: source)

        var target = ApplicationFormData()
        target.companyName = "乙公司"
        target.companyIndustry = "互联网"
        target.companyWebsite = "https://b.example"
        target.position = "乙岗位"
        store.saveApplication(data: target)

        guard let sourceApplication = store.application(id: sourceID) else {
            return XCTFail("Expected source application")
        }
        var moved = store.formData(for: sourceApplication)
        moved.companyName = target.companyName
        store.saveApplication(id: sourceID, data: moved)

        let targetCompany = store.companies.first { $0.name == target.companyName }
        XCTAssertEqual(targetCompany?.industry, "互联网")
        XCTAssertEqual(targetCompany?.website, "https://b.example")
        XCTAssertEqual(store.application(id: sourceID)?.companyID, targetCompany?.id)
    }

    func testPersistenceFailureRollsBackInMemoryMutation() throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(storageURL: url, loadSampleIfEmpty: false)
        var form = ApplicationFormData()
        form.companyName = "回滚测试公司"
        form.position = "工程师"
        form.status = .applied
        let applicationID = store.saveApplication(data: form)
        XCTAssertNil(store.lastSaveError)

        try FileManager.default.removeItem(at: directory)
        try Data("阻止目录创建".utf8).write(to: directory)
        store.updateStatus(applicationID: applicationID, to: .screening)

        XCTAssertEqual(store.application(id: applicationID)?.status, .applied)
        XCTAssertNotNil(store.lastSaveError)
        XCTAssertEqual(store.history(for: applicationID).count, 1)
    }

    func testUnreadableDataFileIsNotOverwrittenByLaterEdits() throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptData = Data("这不是有效 JSON".utf8)
        try corruptData.write(to: url)

        let store = AppStore(storageURL: url, loadSampleIfEmpty: false)
        XCTAssertNotNil(store.lastSaveError)
        var form = ApplicationFormData()
        form.companyName = "不应覆盖"
        form.position = "岗位"
        store.saveApplication(data: form)

        XCTAssertTrue(store.applications.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), corruptData)
        XCTAssertTrue(store.lastSaveError?.contains("避免覆盖") == true)
    }

    func testManualVersionOneRestoreRunsMigration() throws {
        let company = Company(name: "旧备份公司")
        let application = JobApplication(companyID: company.id, position: "旧岗位", status: .applied)
        let oldSnapshot = AppSnapshot(
            schemaVersion: 1,
            companies: [company],
            projects: [],
            applications: [application],
            events: [],
            todos: [],
            statusHistory: [],
            settings: UserSettings(),
            customStages: nil,
            tags: nil,
            resumeVersions: nil
        )

        let migrated = try BackupService.decode(BackupService.encode(oldSnapshot))
        XCTAssertEqual(migrated.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertFalse(migrated.tags?.isEmpty ?? true)
        XCTAssertEqual(migrated.resumeVersions?.first?.isDefault, true)

        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        try store.replace(with: oldSnapshot)
        XCTAssertFalse(store.tags.isEmpty)
        XCTAssertEqual(store.resumeVersions.first?.isDefault, true)
    }

    func testInvalidBackupReferencesAndReminderRangesAreRejected() throws {
        let company = Company(name: "备份校验公司")
        let application = JobApplication(companyID: company.id, position: "岗位", status: .applied)
        let event = ProcessEvent(
            applicationID: application.id,
            type: .interview,
            title: "异常提醒",
            startsAt: Date().addingTimeInterval(86_400),
            reminderMinutes: [Int.max]
        )
        let invalidReminderSnapshot = AppSnapshot(
            companies: [company],
            projects: [],
            applications: [application],
            events: [event],
            todos: [],
            statusHistory: [],
            settings: UserSettings()
        )
        XCTAssertThrowsError(try BackupService.decode(BackupService.encode(invalidReminderSnapshot)))

        let orphanEvent = ProcessEvent(
            applicationID: UUID(),
            type: .interview,
            title: "孤立事件",
            startsAt: Date()
        )
        let invalidReferenceSnapshot = AppSnapshot(
            companies: [company],
            projects: [],
            applications: [application],
            events: [orphanEvent],
            todos: [],
            statusHistory: [],
            settings: UserSettings()
        )
        XCTAssertThrowsError(try BackupService.decode(BackupService.encode(invalidReferenceSnapshot)))
    }

    func testCustomStageTransitionCountsAsFirstResponse() {
        let store = AppStore(storageURL: temporaryURL(), loadSampleIfEmpty: false)
        var form = ApplicationFormData()
        form.companyName = "自定义响应公司"
        form.position = "研发"
        form.status = .applied
        form.appliedAt = Date().addingTimeInterval(-3_600)
        let applicationID = store.saveApplication(data: form)
        let stageID = store.addCustomStage(name: "等待业务反馈", colorKey: "orange", isTerminal: false)
        store.updateCustomStage(applicationID: applicationID, customStageID: stageID)

        guard let application = store.application(id: applicationID) else {
            return XCTFail("Expected application")
        }
        XCTAssertNotNil(store.firstResponseDate(for: application))
    }
}

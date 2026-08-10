import Foundation

enum AppDataLimits {
    static let maximumReminderMinutes = 525_600
    static let maximumCSVBytes = 25 * 1_024 * 1_024
    static let maximumBackupBytes = 100 * 1_024 * 1_024
    static let maximumPrimaryRecords = 100_000
    static let maximumRelatedRecords = 250_000
}

enum ApplicationStatus: String, Codable, CaseIterable, Identifiable {
    case evaluating = "待评估"
    case toApply = "待投递"
    case applied = "已投递"
    case screening = "简历筛选"
    case assessment = "测评/笔试"
    case interviewing = "面试中"
    case waiting = "等待结果"
    case offer = "Offer"
    case accepted = "已接受"
    case rejected = "未通过"
    case withdrawn = "主动放弃"
    case closed = "流程结束"

    var id: String { rawValue }

    var isActive: Bool {
        ![.accepted, .rejected, .withdrawn, .closed].contains(self)
    }

    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

enum RecruitmentProjectStatus: String, Codable, CaseIterable, Identifiable {
    case evaluating = "待评估"
    case open = "开放投递"
    case paused = "暂停"
    case closed = "已截止"

    var id: String { rawValue }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low = "低"
    case medium = "中"
    case high = "高"

    var id: String { rawValue }
    var sortValue: Int { self == .high ? 3 : (self == .medium ? 2 : 1) }
}

enum EventType: String, Codable, CaseIterable, Identifiable {
    case assessment = "在线测评"
    case writtenTest = "笔试"
    case interview = "面试"
    case hrInterview = "HR 面"
    case offerTalk = "Offer 沟通"
    case other = "其他"

    var id: String { rawValue }
    var isInterview: Bool { self == .interview || self == .hrInterview }
}

enum EventResult: String, Codable, CaseIterable, Identifiable {
    case scheduled = "待进行"
    case completed = "已完成"
    case passed = "通过"
    case failed = "未通过"
    case pending = "待定"
    case cancelled = "已取消"

    var id: String { rawValue }

    var isPending: Bool {
        self == .scheduled || self == .pending
    }
}

enum InterviewFormat: String, Codable, CaseIterable, Identifiable {
    case online = "线上"
    case onsite = "线下"
    case phone = "电话"
    case other = "其他"

    var id: String { rawValue }
}

struct CustomStage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorKey: String = "indigo"
    var order: Int = 0
    var isTerminal: Bool = false
    var createdAt: Date = Date()
}

struct JobTag: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorKey: String = "blue"
    var createdAt: Date = Date()
}

struct ResumeVersion: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var target: String = ""
    var filePath: String = ""
    var notes: String = ""
    var isDefault: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct Company: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var industry: String = ""
    var nature: String = ""
    var website: String = ""
    var recruitmentURL: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
}

struct RecruitmentProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var companyID: UUID
    var name: String
    var type: String = "秋招"
    var url: String = ""
    var deadline: Date?
    var status: RecruitmentProjectStatus = .open
    var notes: String = ""
    var createdAt: Date = Date()
}

struct JobApplication: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var companyID: UUID
    var projectID: UUID?
    var position: String
    var category: String = ""
    var department: String = ""
    var location: String = ""
    var jdURL: String = ""
    var channel: String = "官网"
    var referrer: String = ""
    var appliedAt: Date?
    var status: ApplicationStatus = .evaluating
    var customStageID: UUID?
    var tagIDs: [UUID]?
    var resumeVersionID: UUID?
    var priority: Priority = .medium
    var salary: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
}

struct ProcessEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var applicationID: UUID
    var type: EventType
    var title: String
    var round: Int?
    var startsAt: Date
    var endsAt: Date?
    var format: InterviewFormat = .online
    var meetingURL: String = ""
    var location: String = ""
    var interviewer: String = ""
    var result: EventResult = .scheduled
    var questions: String = ""
    var review: String = ""
    var notes: String = ""
    var reminderMinutes: [Int] = [1_440, 120]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var applicationID: UUID?
    var title: String
    var dueAt: Date?
    var priority: Priority = .medium
    var isCompleted: Bool = false
    var notes: String = ""
    var reminderMinutes: Int? = 120
    var createdAt: Date = Date()
    var completedAt: Date?
}

struct StatusHistory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var applicationID: UUID
    var fromStatus: ApplicationStatus?
    var toStatus: ApplicationStatus
    var fromCustomName: String?
    var toCustomName: String?
    var changedAt: Date = Date()
    var note: String = ""
}

struct UserSettings: Codable, Hashable {
    var notificationsEnabled = false
    var staleDays = 7
    var defaultReminderMinutes = 120
}

struct AppSnapshot: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion = Self.currentSchemaVersion
    var companies: [Company]
    var projects: [RecruitmentProject]
    var applications: [JobApplication]
    var events: [ProcessEvent]
    var todos: [TodoItem]
    var statusHistory: [StatusHistory]
    var settings: UserSettings
    var customStages: [CustomStage]?
    var tags: [JobTag]?
    var resumeVersions: [ResumeVersion]?
}

struct ApplicationFormData {
    var companyName = ""
    var companyIndustry = ""
    var companyNature = ""
    var companyWebsite = ""
    var recruitmentURL = ""
    var projectName = ""
    var projectType = "秋招"
    var projectURL = ""
    var projectDeadline: Date?
    var position = ""
    var category = ""
    var department = ""
    var location = ""
    var jdURL = ""
    var channel = "官网"
    var referrer = ""
    var appliedAt: Date?
    var status: ApplicationStatus = .evaluating
    var customStageID: UUID?
    var tagIDs: Set<UUID> = []
    var resumeVersionID: UUID?
    var priority: Priority = .medium
    var salary = ""
    var notes = ""
    var importedCustomStageName = ""
    var importedTagNames: [String] = []
    var importedResumeName = ""
}

struct ResumeFormData {
    var name = ""
    var target = ""
    var filePath = ""
    var notes = ""
    var isDefault = false
}

struct EventFormData {
    var type: EventType = .interview
    var title = "一面"
    var round: Int? = 1
    var startsAt = Date().addingTimeInterval(86_400)
    var endsAt: Date?
    var format: InterviewFormat = .online
    var meetingURL = ""
    var location = ""
    var interviewer = ""
    var result: EventResult = .scheduled
    var questions = ""
    var review = ""
    var notes = ""
    var reminderMinutes: [Int] = [1_440, 120]
}

struct TodoFormData {
    var applicationID: UUID?
    var title = ""
    var dueAt: Date? = Date().addingTimeInterval(86_400)
    var priority: Priority = .medium
    var notes = ""
    var reminderMinutes: Int? = 120
}

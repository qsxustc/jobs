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

    var analysisCategory: ApplicationAnalysisCategory {
        switch self {
        case .evaluating, .toApply:
            return .notSubmitted
        case .applied, .screening, .assessment, .waiting:
            return .submitted
        case .interviewing:
            return .interview
        case .offer, .accepted:
            return .offer
        case .rejected, .withdrawn, .closed:
            return .ended
        }
    }
}

/// A stable, user-configurable reporting dimension shared by built-in and
/// custom workflow stages. Custom stage names remain visible in the workflow;
/// this category only controls how they contribute to dashboard analytics.
enum ApplicationAnalysisCategory: String, Codable, CaseIterable, Identifiable {
    case notSubmitted = "未投递"
    case submitted = "已投递"
    case interview = "面试"
    case offer = "Offer"
    case ended = "结束"

    var id: String { rawValue }
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
    var id: UUID
    var name: String
    var colorKey: String
    var order: Int
    var isTerminal: Bool
    var analysisCategory: ApplicationAnalysisCategory
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorKey: String = "indigo",
        order: Int = 0,
        isTerminal: Bool = false,
        analysisCategory: ApplicationAnalysisCategory = .submitted,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorKey = colorKey
        self.order = order
        self.isTerminal = isTerminal
        self.analysisCategory = analysisCategory
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorKey, order, isTerminal, analysisCategory, createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        colorKey = try values.decodeIfPresent(String.self, forKey: .colorKey) ?? "indigo"
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
        isTerminal = try values.decodeIfPresent(Bool.self, forKey: .isTerminal) ?? false
        analysisCategory = try values.decodeIfPresent(ApplicationAnalysisCategory.self, forKey: .analysisCategory)
            ?? (isTerminal ? .ended : .submitted)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
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
    /// The pasted job description. Optional keeps snapshots created before this
    /// field was introduced decodable without a schema migration.
    var jdText: String?
    var requirements: String?
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
    var notificationsEnabled: Bool
    var staleDays: Int
    var defaultReminderMinutes: Int
    var backgroundIdleMinutes: Int

    init(
        notificationsEnabled: Bool = false,
        staleDays: Int = 7,
        defaultReminderMinutes: Int = 120,
        backgroundIdleMinutes: Int = 15
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.staleDays = staleDays
        self.defaultReminderMinutes = defaultReminderMinutes
        self.backgroundIdleMinutes = backgroundIdleMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case notificationsEnabled
        case staleDays
        case defaultReminderMinutes
        case backgroundIdleMinutes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        staleDays = try values.decodeIfPresent(Int.self, forKey: .staleDays) ?? 7
        defaultReminderMinutes = try values.decodeIfPresent(Int.self, forKey: .defaultReminderMinutes) ?? 120
        backgroundIdleMinutes = try values.decodeIfPresent(Int.self, forKey: .backgroundIdleMinutes) ?? 15
    }
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
    var selectedCompanyID: UUID?
    var companyName = ""
    var companyIndustry = ""
    var companyNature = ""
    var companyWebsite = ""
    var recruitmentURL = ""
    var selectedProjectID: UUID?
    var projectName = ""
    var projectType = "秋招"
    var projectURL = ""
    var projectDeadline: Date?
    var position = ""
    var category = ""
    var department = ""
    var location = ""
    var jdURL = ""
    var jdText = ""
    var requirements = ""
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

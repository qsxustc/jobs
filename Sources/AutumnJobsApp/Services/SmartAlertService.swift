import Foundation

enum SmartAlertSeverity: Int, Comparable {
    case info = 1
    case warning = 2
    case critical = 3

    static func < (lhs: SmartAlertSeverity, rhs: SmartAlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SmartAlertKind: Equatable {
    case overdueTodo
    case upcomingEvent
    case staleApplication
    case missingReview
    case projectDeadline
}

struct SmartAlertItem: Identifiable {
    let id: String
    let kind: SmartAlertKind
    let severity: SmartAlertSeverity
    let title: String
    let message: String
    let date: Date?
    var applicationID: UUID?
    var eventID: UUID?
    var todoID: UUID?
}

enum SmartAlertService {
    @MainActor
    static func items(store: AppStore, now: Date = Date()) -> [SmartAlertItem] {
        var result: [SmartAlertItem] = []
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let nextThreeDays = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        let staleThreshold = calendar.date(byAdding: .day, value: -store.settings.staleDays, to: now) ?? now

        for todo in store.openTodos {
            guard store.application(id: todo.applicationID)?.isArchived != true else { continue }
            guard let dueAt = todo.dueAt, dueAt < now else { continue }
            result.append(SmartAlertItem(
                id: "todo-\(todo.id)",
                kind: .overdueTodo,
                severity: .critical,
                title: "待办已经逾期",
                message: todo.title,
                date: dueAt,
                applicationID: todo.applicationID,
                todoID: todo.id
            ))
        }

        for event in store.events where event.result != .cancelled {
            guard let application = store.application(id: event.applicationID) else { continue }
            guard !application.isArchived else { continue }
            let company = store.company(for: application)?.name ?? "未知公司"
            if event.result.isPending, event.startsAt >= now && event.startsAt <= nextDay {
                result.append(SmartAlertItem(
                    id: "upcoming-\(event.id)",
                    kind: .upcomingEvent,
                    severity: .warning,
                    title: "24 小时内有\(event.type.rawValue)",
                    message: "\(company) · \(application.position) · \(event.title)",
                    date: event.startsAt,
                    applicationID: application.id,
                    eventID: event.id
                ))
            }
            if event.type.isInterview,
               event.startsAt < now,
               event.review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(SmartAlertItem(
                    id: "review-\(event.id)",
                    kind: .missingReview,
                    severity: .info,
                    title: "面试后还没有复盘",
                    message: "\(company) · \(event.title)",
                    date: event.startsAt,
                    applicationID: application.id,
                    eventID: event.id
                ))
            }
        }

        for application in store.activeApplications where store.isActive(application) && application.updatedAt < staleThreshold {
            let company = store.company(for: application)?.name ?? "未知公司"
            result.append(SmartAlertItem(
                id: "stale-\(application.id)",
                kind: .staleApplication,
                severity: .warning,
                title: "流程需要跟进",
                message: "\(company) · \(application.position) 已超过 \(store.settings.staleDays) 天未更新",
                date: application.updatedAt,
                applicationID: application.id
            ))
        }

        for project in store.projects where project.status == .open {
            guard store.activeApplications.contains(where: {
                $0.projectID == project.id && store.isActive($0)
            }) else { continue }
            guard let deadline = project.deadline, deadline >= now, deadline <= nextThreeDays else { continue }
            let company = store.company(id: project.companyID)?.name ?? "未知公司"
            result.append(SmartAlertItem(
                id: "project-\(project.id)",
                kind: .projectDeadline,
                severity: .warning,
                title: "招聘项目即将截止",
                message: "\(company) · \(project.name)",
                date: deadline
            ))
        }

        return result.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture)
        }
    }
}

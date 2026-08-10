import Foundation
import UserNotifications

struct ReminderRefreshResult: Sendable {
    let scheduledCount: Int
    let failedCount: Int
    let deferredCount: Int
}

private actor ReminderRefreshGate {
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var waiters: [CheckedContinuation<ReminderRefreshResult, Never>] = []

    func run(
        _ operation: @escaping @MainActor @Sendable () async -> ReminderRefreshResult
    ) async -> ReminderRefreshResult {
        if isRefreshing {
            needsAnotherRefresh = true
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        isRefreshing = true
        var result = await operation()
        while needsAnotherRefresh {
            needsAnotherRefresh = false
            result = await operation()
        }
        isRefreshing = false

        let completedWaiters = waiters
        waiters.removeAll()
        for waiter in completedWaiters {
            waiter.resume(returning: result)
        }
        return result
    }
}

private struct ReminderApplicationContext {
    let companyName: String
    let position: String
    let isArchived: Bool
}

private struct ReminderCandidate {
    let fireDate: Date
    let identifier: String
    let title: String
    let body: String
}

enum ReminderService {
    private static let prefix = "autumnjobs."
    private static let maximumScheduledRequests = 60
    private static let refreshGate = ReminderRefreshGate()

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    @discardableResult
    @MainActor
    static func refresh(store: AppStore) async -> ReminderRefreshResult {
        await refreshGate.run {
            await performRefresh(store: store)
        }
    }

    @MainActor
    private static func performRefresh(store: AppStore) async -> ReminderRefreshResult {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        store.lastNotificationError = nil
        guard store.settings.notificationsEnabled else {
            return ReminderRefreshResult(scheduledCount: 0, failedCount: 0, deferredCount: 0)
        }

        guard await isAuthorized() else {
            var updatedSettings = store.settings
            updatedSettings.notificationsEnabled = false
            store.updateSettings(updatedSettings)
            store.lastNotificationError = "系统通知权限未开启，请前往“系统设置 → 通知”重新授权。"
            return ReminderRefreshResult(scheduledCount: 0, failedCount: 0, deferredCount: 0)
        }

        let now = Date()
        var companyNamesByID: [UUID: String] = [:]
        companyNamesByID.reserveCapacity(store.companies.count)
        for company in store.companies {
            companyNamesByID[company.id] = company.name
        }

        var applicationContextsByID: [UUID: ReminderApplicationContext] = [:]
        applicationContextsByID.reserveCapacity(store.applications.count)
        for application in store.applications {
            applicationContextsByID[application.id] = ReminderApplicationContext(
                companyName: companyNamesByID[application.companyID] ?? "求职事项",
                position: application.position,
                isArchived: application.isArchived
            )
        }

        var candidates: [ReminderCandidate] = []
        candidates.reserveCapacity(maximumScheduledRequests)
        var candidateCount = 0
        for event in store.events where event.startsAt > now && event.result.isPending {
            guard let application = applicationContextsByID[event.applicationID],
                  !application.isArchived else { continue }
            for minutes in Set(event.reminderMinutes) where minutes > 0 {
                guard minutes <= AppDataLimits.maximumReminderMinutes else { continue }
                let fireDate = event.startsAt.addingTimeInterval(-TimeInterval(minutes) * 60)
                guard fireDate > now else { continue }
                candidateCount += 1
                insertIfSooner(ReminderCandidate(
                    fireDate: fireDate,
                    identifier: "\(prefix)event.\(event.id.uuidString).\(minutes)",
                    title: "\(application.companyName) · \(event.title)",
                    body: "\(application.position)将在\(reminderLabel(minutes))后开始"
                ), into: &candidates)
            }
        }

        for todo in store.todos where !todo.isCompleted {
            if let applicationID = todo.applicationID,
               applicationContextsByID[applicationID]?.isArchived == true {
                continue
            }
            guard let dueAt = todo.dueAt, let minutes = todo.reminderMinutes else { continue }
            guard (1...AppDataLimits.maximumReminderMinutes).contains(minutes) else { continue }
            let fireDate = dueAt.addingTimeInterval(-TimeInterval(minutes) * 60)
            guard fireDate > now else { continue }
            candidateCount += 1
            insertIfSooner(ReminderCandidate(
                fireDate: fireDate,
                identifier: "\(prefix)todo.\(todo.id.uuidString)",
                title: "待办提醒",
                body: "\(todo.title)将在\(reminderLabel(minutes))后到期"
            ), into: &candidates)
        }

        var scheduledCount = 0
        var failedCount = 0
        var firstError: Error?
        for candidate in candidates {
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: candidate.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: candidate.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                scheduledCount += 1
            } catch {
                failedCount += 1
                if firstError == nil { firstError = error }
            }
        }

        let deferredCount = max(0, candidateCount - candidates.count)
        if failedCount > 0 {
            store.lastNotificationError = "有 \(failedCount) 条提醒调度失败：\(firstError?.localizedDescription ?? "未知错误")"
        } else if deferredCount > 0 {
            store.lastNotificationError = "提醒数量较多，仅安排了最近的 \(maximumScheduledRequests) 条；更远的提醒将在后续刷新时安排。"
        }
        return ReminderRefreshResult(
            scheduledCount: scheduledCount,
            failedCount: failedCount,
            deferredCount: deferredCount
        )
    }

    private static func insertIfSooner(
        _ candidate: ReminderCandidate,
        into candidates: inout [ReminderCandidate]
    ) {
        if candidates.count == maximumScheduledRequests,
           let last = candidates.last,
           candidate.fireDate >= last.fireDate {
            return
        }

        let insertionIndex = candidates.partitioningIndex {
            $0.fireDate >= candidate.fireDate
        }
        candidates.insert(candidate, at: insertionIndex)
        if candidates.count > maximumScheduledRequests {
            candidates.removeLast()
        }
    }

    private static func reminderLabel(_ minutes: Int) -> String {
        if minutes >= 1_440 { return "\(minutes / 1_440)天" }
        if minutes >= 60 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }
}

private extension Array {
    func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Index {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound != upperBound {
            let distance = self.distance(from: lowerBound, to: upperBound)
            let middle = index(lowerBound, offsetBy: distance / 2)
            if belongsInSecondPartition(self[middle]) {
                upperBound = middle
            } else {
                lowerBound = index(after: middle)
            }
        }
        return lowerBound
    }
}

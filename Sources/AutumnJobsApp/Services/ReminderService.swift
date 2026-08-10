import Foundation
import UserNotifications

struct ReminderRefreshResult {
    let scheduledCount: Int
    let failedCount: Int
    let deferredCount: Int
}

private actor ReminderRefreshLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum ReminderService {
    private static let prefix = "autumnjobs."
    private static let maximumScheduledRequests = 60
    private static let refreshLock = ReminderRefreshLock()

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
        await refreshLock.lock()
        let result = await performRefresh(store: store)
        await refreshLock.unlock()
        return result
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
        var candidates: [(fireDate: Date, request: UNNotificationRequest)] = []
        for event in store.events where event.startsAt > now && event.result.isPending {
            guard let application = store.application(id: event.applicationID) else { continue }
            guard !application.isArchived else { continue }
            let company = store.company(for: application)?.name ?? "求职事项"
            for minutes in Set(event.reminderMinutes) where minutes > 0 {
                guard minutes <= AppDataLimits.maximumReminderMinutes else { continue }
                let fireDate = event.startsAt.addingTimeInterval(-TimeInterval(minutes) * 60)
                guard fireDate > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(company) · \(event.title)"
                content.body = "\(application.position)将在\(reminderLabel(minutes))后开始"
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(prefix)event.\(event.id.uuidString).\(minutes)",
                    content: content,
                    trigger: trigger
                )
                candidates.append((fireDate, request))
            }
        }

        for todo in store.todos where !todo.isCompleted {
            guard store.application(id: todo.applicationID)?.isArchived != true else { continue }
            guard let dueAt = todo.dueAt, let minutes = todo.reminderMinutes else { continue }
            guard (1...AppDataLimits.maximumReminderMinutes).contains(minutes) else { continue }
            let fireDate = dueAt.addingTimeInterval(-TimeInterval(minutes) * 60)
            guard fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "待办提醒"
            content.body = "\(todo.title)将在\(reminderLabel(minutes))后到期"
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(prefix)todo.\(todo.id.uuidString)",
                content: content,
                trigger: trigger
            )
            candidates.append((fireDate, request))
        }

        candidates.sort { $0.fireDate < $1.fireDate }
        let selected = candidates.prefix(maximumScheduledRequests)
        var scheduledCount = 0
        var failedCount = 0
        var firstError: Error?
        for candidate in selected {
            do {
                try await center.add(candidate.request)
                scheduledCount += 1
            } catch {
                failedCount += 1
                if firstError == nil { firstError = error }
            }
        }

        let deferredCount = max(0, candidates.count - selected.count)
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

    private static func reminderLabel(_ minutes: Int) -> String {
        if minutes >= 1_440 { return "\(minutes / 1_440)天" }
        if minutes >= 60 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }
}

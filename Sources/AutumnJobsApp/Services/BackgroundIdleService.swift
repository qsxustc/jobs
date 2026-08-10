import AppKit

/// Frees the process after the user has closed every app window for a while.
/// When windows remain open, macOS App Nap is the safer suspension mechanism.
@MainActor
final class BackgroundIdleService: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    private let hasVisibleWindows: @MainActor () -> Bool
    private let sleep: @MainActor (Duration) async throws -> Void
    private let terminate: @MainActor () -> Void
    private var idleTask: Task<Void, Never>?

    override init() {
        hasVisibleWindows = {
            NSApp.windows.contains { $0.isVisible }
        }
        sleep = { duration in
            try await Task.sleep(for: duration)
        }
        terminate = {
            NSApp.terminate(nil)
        }
        super.init()
    }

    init(
        hasVisibleWindows: @escaping @MainActor () -> Bool,
        sleep: @escaping @MainActor (Duration) async throws -> Void,
        terminate: @escaping @MainActor () -> Void
    ) {
        self.hasVisibleWindows = hasVisibleWindows
        self.sleep = sleep
        self.terminate = terminate
        super.init()
    }

    func attach(store: AppStore) {
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelIdleTask()
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        cancelIdleTask()
    }

    @objc
    private func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            // willClose is sent before the window stops being visible.
            await Task.yield()
            self?.scheduleIdleExitIfNeeded()
        }
    }

    func scheduleIdleExitIfNeeded() {
        cancelIdleTask()
        let minutes = store?.settings.backgroundIdleMinutes ?? 0
        guard minutes > 0, !hasVisibleWindows() else { return }

        idleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(.seconds(minutes * 60))
            } catch {
                return
            }
            guard self.store?.settings.backgroundIdleMinutes ?? 0 > 0,
                  !self.hasVisibleWindows() else { return }
            self.terminate()
        }
    }

    private func cancelIdleTask() {
        idleTask?.cancel()
        idleTask = nil
    }
}

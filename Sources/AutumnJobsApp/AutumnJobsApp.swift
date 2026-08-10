import SwiftUI

@main
struct AutumnJobs: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(BackgroundIdleService.self) private var backgroundIdleService

    var body: some Scene {
        WindowGroup("秋招助手") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1_080, minHeight: 700)
                .task {
                    backgroundIdleService.attach(store: store)
                    await ReminderService.refresh(store: store)
                }
        }
        .defaultSize(width: 1_280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建投递") {
                    NotificationCenter.default.post(name: .newApplication, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newApplication = Notification.Name("AutumnJobs.newApplication")
}

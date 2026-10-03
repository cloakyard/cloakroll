import AppKit
import SwiftUI

@main
struct CloakRollApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let highContrast = arguments.contains("--verify-increased-contrast")
        if arguments.contains("--verify-dark-appearance") {
            NSApplication.shared.appearance = NSAppearance(
                named: highContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
            )
        } else if arguments.contains("--verify-light-appearance") {
            NSApplication.shared.appearance = NSAppearance(
                named: highContrast ? .accessibilityHighContrastAqua : .aqua
            )
        }
        #endif
    }

    var body: some Scene {
        Window("CloakRoll", id: "main") {
            RootView()
                .environment(model)
                .tint(Design.accent)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    appDelegate.onTerminate = model.shutdown
                    appDelegate.backup = model.backup
                    await model.bootstrap()
                }
        }
        .defaultSize(width: 1_100, height: 740)
        .commands { LibraryCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Design.accent)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?
    weak var backup: LibraryBackupController?
    private var isWaitingToQuit = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestTermination { sender.reply(toApplicationShouldTerminate: $0) }
    }

    /// Keeps the AppKit reply at the edge so lifecycle tests never terminate their host.
    func requestTermination(reply: @escaping @MainActor (Bool) -> Void) -> NSApplication.TerminateReply {
        guard !isWaitingToQuit else { return .terminateLater }
        guard let backup, backup.isBusy else { return .terminateNow }
        isWaitingToQuit = true
        backup.cancel()
        Task {
            await backup.waitUntilStopped()
            isWaitingToQuit = false
            reply(true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { onTerminate?() }
}

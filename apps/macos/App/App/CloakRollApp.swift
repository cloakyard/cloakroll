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

    func applicationWillTerminate(_ notification: Notification) { onTerminate?() }
}

struct LibraryCommands: Commands {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CloakRoll") {
                model.settingsTab = .about
                openSettings()
            }
        }
        CommandMenu("Library") {
            Button("Show Info") { model.showSelectedInfo() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(model.selection.selectedIDs.isEmpty)
            Button("Deselect All") { model.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.selection.selectedIDs.isEmpty)
        }
        #if DEBUG
        CommandMenu("Development") {
            Button("Connected iPhone") { model.startLive() }
            Divider()
            Button("Sample Library · 20 Items") { Task { await model.loadSample(count: 20) } }
            Button("Sample Library · 1,200 Items") { Task { await model.loadSample(count: 1_200) } }
            Button("Sample Library · 100,000 Items") { Task { await model.loadSample(count: 100_000) } }
            Divider()
            Button("No Device") { Task { await model.loadSample(count: 0, state: .disconnected) } }
            Button("Restricted Device") { Task { await model.loadSample(count: 0, state: .restricted) } }
            Button("Disconnected Library") { model.deviceState = .unavailable }
            Button("Sample Backup Progress") { model.sampleProgress.toggle() }
            Divider()
            Button("Compact Window") {
                NSApplication.shared.mainWindow?.setContentSize(NSSize(width: 860, height: 560))
            }
            Button("Standard Window") {
                NSApplication.shared.mainWindow?.setContentSize(NSSize(width: 1_100, height: 740))
            }
        }
        #endif
    }
}

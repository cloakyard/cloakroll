#if DEBUG
import AppKit
import SwiftUI

struct DevelopmentCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Development") {
            Group {
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
            }
            .disabled(model.backup.isBusy)
            Button("Log Thumbnail Metrics") { Task { await model.thumbnails.logMetrics() } }
            Divider()
            Button("Compact Window") {
                NSApplication.shared.mainWindow?.setContentSize(NSSize(width: 860, height: 560))
            }
            Button("Standard Window") {
                NSApplication.shared.mainWindow?.setContentSize(NSSize(width: 1_100, height: 740))
            }
            Menu("Appearance") {
                Button("System") { NSApplication.shared.appearance = nil }
                Button("Light") { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
                Button("Dark") { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
            }
        }
    }
}
#endif

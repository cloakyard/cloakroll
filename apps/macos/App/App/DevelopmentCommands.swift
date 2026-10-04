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
                Menu("Sample Backup Progress") {
                    ForEach(BackupProgressExample.allCases, id: \.self) { example in
                        Button(example.rawValue) {
                            Task {
                                await model.loadSample(count: 20)
                                guard model.isSample, !model.backup.isBusy else { return }
                                model.sampleProgressExample = example
                                model.sampleProgress = true
                            }
                        }
                    }
                    Divider()
                    Button("Hide Sample Progress") { model.sampleProgress = false }
                }
                Menu("Media Info Examples") {
                    Button("Long Filenames and Many Originals") {
                        Task { await MediaInfoExamples.show(.longFilenames, in: model) }
                    }
                    Button("Missing Metadata and Preview") {
                        Task { await MediaInfoExamples.show(.missingMetadata, in: model) }
                    }
                }
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

#if DEBUG
import SwiftUI

/// Uses the production AppKit renderer without starting a backup or changing the Dock.
struct BackupDockExamples: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Dock Progress Examples").font(.headline)
            HStack(spacing: 24) {
                example("Preparing", percent: nil)
                example("Copying", percent: 33)
                example("Almost received", percent: 99)
                example("Verifying", percent: 100)
            }
            Text("Sample states. A full ring still waits for verification and saved history.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }

    private func example(_ title: String, percent: Int?) -> some View {
        VStack {
            DockExampleTile(percent: percent).frame(width: 96, height: 96)
            Text(title).font(.caption)
        }
    }
}

private struct DockExampleTile: NSViewRepresentable {
    let percent: Int?
    func makeNSView(context: Context) -> BackupDockTileView { BackupDockTileView() }
    func updateNSView(_ view: BackupDockTileView, context: Context) {
        view.state = BackupDockState(percent: percent, isStopping: false)
        view.needsDisplay = true
    }
}
#endif

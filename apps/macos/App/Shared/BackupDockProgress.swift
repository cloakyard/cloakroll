import AppKit
import BackupEngine
import Observation

/// Display-only byte progress. A full ring still means data received, not backup success.
struct BackupDockState: Equatable {
    let percent: Int?
    let isStopping: Bool

    static func make(snapshot: BackupSnapshot?, isBackingUp: Bool, isStopping: Bool) -> Self? {
        guard isBackingUp, let snapshot, ![.idle, .failed, .cancelled].contains(snapshot.phase) else { return nil }
        return Self(percent: BackupProgressPresentation(snapshot: snapshot).wholePercent,
                    isStopping: isStopping || snapshot.phase == .cancelling)
    }
}

/// App-owned observation continues when the library window is closed or backgrounded.
@MainActor
final class BackupDockProgress {
    private weak var model: AppModel?
    private let render: (BackupDockState?) -> Void
    private var lastDrawn: BackupDockState?
    private var isObserving = true

    init(model: AppModel, render: @escaping (BackupDockState?) -> Void) {
        self.model = model
        self.render = render
        observe()
    }

    func stop() {
        isObserving = false
        model = nil
        if lastDrawn != nil { render(nil) }
        lastDrawn = nil
    }

    private func observe() {
        guard isObserving, let model else { return }
        withObservationTracking {
            var state = BackupDockState.make(snapshot: model.backup.snapshot, isBackingUp: model.backup.isBackingUp,
                                             isStopping: model.backup.isStopping)
            #if DEBUG
            // Explicit preview only; never starts a transfer or writes backup evidence.
            if model.isSample, model.sampleProgress {
                let example = model.sampleProgressExample.presentation
                state = BackupDockState.make(snapshot: example.snapshot, isBackingUp: true, isStopping: example.isStopping)
            }
            #endif
            if state != lastDrawn { lastDrawn = state; render(state) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}

@MainActor
final class BackupDockRenderer {
    private let view = BackupDockTileView()

    func render(_ state: BackupDockState?) {
        let tile = NSApplication.shared.dockTile
        tile.badgeLabel = nil
        if let state {
            view.frame = NSRect(origin: .zero, size: tile.size)
            view.state = state
            view.needsDisplay = true
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

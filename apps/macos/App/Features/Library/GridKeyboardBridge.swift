import AppKit
import SwiftUI

/// A narrow AppKit responder supplies Finder keyboard semantics to the SwiftUI lazy grid.
/// It becomes first responder only after a grid click; text fields keep their native editing commands.
@MainActor
final class GridKeyboardController {
    weak var responder: GridKeyView?

    func focus() { responder?.window?.makeFirstResponder(responder) }
}

struct GridKeyboardBridge: NSViewRepresentable {
    let controller: GridKeyboardController
    let onMove: (GridDirection, Bool) -> Void
    let onSelectAll: () -> Void
    let onPreview: () -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> GridKeyView {
        let view = GridKeyView()
        controller.responder = view
        return view
    }

    func updateNSView(_ view: GridKeyView, context: Context) {
        view.onMove = onMove
        view.onSelectAll = onSelectAll
        view.onPreview = onPreview
        view.onClear = onClear
    }
}

final class GridKeyView: NSView {
    var onMove: ((GridDirection, Bool) -> Void)?
    var onSelectAll: (() -> Void)?
    var onPreview: (() -> Void)?
    var onClear: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch GridKeyAction(event: event) {
        case .move(let direction, let extending): onMove?(direction, extending)
        case .preview: onPreview?()
        case .clear: onClear?()
        case nil: super.keyDown(with: event)
        }
    }

    override func selectAll(_ sender: Any?) { onSelectAll?() }
}

/// Leave system shortcuts, VoiceOver chords and text editing to the responder chain.
enum GridKeyAction: Equatable {
    case move(GridDirection, extending: Bool), preview, clear

    init?(event: NSEvent) {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let extending = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: self = .move(.left, extending: extending)
        case 124: self = .move(.right, extending: extending)
        case 125: self = .move(.down, extending: extending)
        case 126: self = .move(.up, extending: extending)
        case 49 where !extending: self = .preview
        case 53 where !extending: self = .clear
        default: return nil
        }
    }
}

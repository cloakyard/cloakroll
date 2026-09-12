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
    let columns: Int
    let onMove: (Int, Bool) -> Void
    let onSelectAll: () -> Void
    let onPreview: () -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> GridKeyView {
        let view = GridKeyView()
        controller.responder = view
        return view
    }

    func updateNSView(_ view: GridKeyView, context: Context) {
        view.columns = columns
        view.onMove = onMove
        view.onSelectAll = onSelectAll
        view.onPreview = onPreview
        view.onClear = onClear
    }
}

final class GridKeyView: NSView {
    var columns = 1
    var onMove: ((Int, Bool) -> Void)?
    var onSelectAll: (() -> Void)?
    var onPreview: (() -> Void)?
    var onClear: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let offset: Int
        switch event.keyCode {
        case 123: offset = -1
        case 124: offset = 1
        case 125: offset = columns
        case 126: offset = -columns
        case 49: onPreview?(); return
        case 53: onClear?(); return
        default: super.keyDown(with: event); return
        }
        onMove?(offset, event.modifierFlags.contains(.shift))
    }

    override func selectAll(_ sender: Any?) { onSelectAll?() }
}

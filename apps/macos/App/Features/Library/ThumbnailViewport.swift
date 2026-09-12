import SwiftUI

enum ThumbnailDemand: Equatable {
    case visible, prefetch, none

    static func classify(frame: CGRect, viewport: CGRect) -> Self {
        guard !frame.isEmpty, !viewport.isEmpty else { return .none }
        if frame.intersects(viewport) { return .visible }
        // One row above and two below: bounded nearby work, with no speculative full-library pass.
        let nearby = CGRect(
            x: viewport.minX, y: viewport.minY - frame.height,
            width: viewport.width, height: viewport.height + frame.height * 3
        )
        return frame.intersects(nearby) ? .prefetch : .none
    }
}

/// Geometry is reduced to three bands; pixel-by-pixel scrolling does not publish new state.
struct ThumbnailViewport: ViewModifier {
    nonisolated static let coordinateSpace = "libraryThumbnailViewport"
    let size: CGSize
    @Binding var demand: ThumbnailDemand

    func body(content: Content) -> some View {
        let viewport = CGRect(origin: .zero, size: size)
        content
            .onGeometryChange(for: ThumbnailDemand.self) { geometry in
                ThumbnailDemand.classify(frame: geometry.frame(in: .named(Self.coordinateSpace)), viewport: viewport)
            } action: { demand = $0 }
    }
}

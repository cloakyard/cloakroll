import CoreGraphics
import Observation
import ThumbnailPipeline

/// A nearby cell can hold its ready bitmap through the transition into the viewport.
/// Far cells release it; a changed key prevents an older request from replacing current content.
@MainActor @Observable
final class ThumbnailPresentation {
    private(set) var image: CGImage?
    @ObservationIgnored private var preparedKey: ThumbnailKey?

    /// Returns whether this demand still needs an image. Promotion/demotion of an unchanged
    /// prepared image is synchronous and never clears it while another request is scheduled.
    func prepare(key: ThumbnailKey?, demand: ThumbnailDemand) -> Bool {
        guard demand != .none, let key else {
            reset()
            return false
        }
        if preparedKey != key {
            preparedKey = key
            image = nil
        }
        return image == nil
    }

    func accept(_ image: CGImage?, for key: ThumbnailKey) {
        guard preparedKey == key else { return }
        self.image = image
    }

    func reset() {
        preparedKey = nil
        image = nil
    }
}

import CoreGraphics
import ImageIO
import MediaModels
import SwiftUI

/// Cell-owned decoded thumbnails. Requests are asynchronous and cancelled when the cell leaves
/// use; original media is never requested to render either this view or the Info sheet.
struct MediaThumbnail: View {
    let asset: MediaAsset
    var contentMode: ContentMode = .fill
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?
    @State private var loadedKey: ThumbnailIdentity?

    var body: some View {
        Group {
            if model.isSample {
                SampleThumbnail(asset: asset)
            } else if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Design.cardFill)
                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }
        .accessibilityHidden(true)
        .task(id: request) { await load(request) }
        .onDisappear {
            image = nil
            loadedKey = nil
        }
    }

    private var request: ThumbnailRequest {
        ThumbnailRequest(
            identity: ThumbnailIdentity(
                resourceID: asset.primaryResourceID ?? asset.id,
                sessionID: model.catalogSessionID,
                byteCount: asset.primaryResource?.byteCount ?? 0,
                filename: asset.filename
            ),
            available: !model.isSample && model.deviceState == .ready
        )
    }

    private func load(_ request: ThumbnailRequest) async {
        if loadedKey != request.identity { image = nil }
        guard request.available else { return }
        while !Task.isCancelled {
            do {
                let data = try await model.thumbnailData(for: asset, maximumPixelSize: 512)
                let decoded = await Task.detached(priority: .userInitiated) {
                    ThumbnailDecoder.decode(data, maximumPixelSize: 512)
                }.value
                guard !Task.isCancelled, self.request == request else { return }
                image = decoded
                loadedKey = request.identity
                return
            } catch MediaSourceError.thumbnailQueueFull {
                // Backpressure is transient. Keep a visible cell eligible without growing the
                // device queue, and stop waiting immediately when SwiftUI cancels this task.
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            } catch {
                // Missing thumbnails are a normal source limitation. Metadata remains useful.
                return
            }
        }
    }
}

private struct ThumbnailIdentity: Hashable {
    let resourceID: String
    let sessionID: UUID?
    let byteCount: Int64
    let filename: String
}

private struct ThumbnailRequest: Equatable {
    let identity: ThumbnailIdentity
    let available: Bool
}

enum ThumbnailDecoder {
    static func decode(_ data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

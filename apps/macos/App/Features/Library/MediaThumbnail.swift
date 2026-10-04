import CoreGraphics
import MediaModels
import SwiftUI
import ThumbnailPipeline

/// Cells retain only their displayed bitmap. Shared caches serve revisits and Info.
struct MediaThumbnail: View {
    let asset: MediaAsset
    var contentMode: ContentMode = .fill
    var demand: ThumbnailDemand = .visible
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?
    @State private var loadedKey: ThumbnailKey?

    var body: some View {
        Group {
            if model.isSample {
                SampleThumbnail(asset: asset, contentMode: contentMode)
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
            asset: asset, sessionID: model.catalogSessionID,
            reusableIdentity: model.device?.identity?.isPersistent == true
                ? asset.primaryResourceID.flatMap { model.thumbnailReuseIDs[$0] } : nil,
            available: !model.isSample && model.deviceState == .ready,
            demand: demand
        )
    }

    private func load(_ request: ThumbnailRequest) async {
        guard request.demand != .none else {
            image = nil
            loadedKey = nil
            return
        }
        let key = ThumbnailKey(asset: request.asset, sessionID: request.sessionID, reusableIdentity: request.reusableIdentity)
        if loadedKey != key || request.demand != .visible {
            image = nil
            loadedKey = nil
        }
        guard request.available, request.demand != .none, let key else { return }
        if loadedKey == key, image != nil { return }
        while !Task.isCancelled {
            do {
                let load: @Sendable () async throws -> Data = { [model] in
                    try await model.thumbnailData(for: key)
                }
                if request.demand == .prefetch {
                    try await model.thumbnails.prefetch(for: key, load: load)
                } else {
                    let decoded = try await model.thumbnails.image(for: key, load: load)
                    guard !Task.isCancelled, self.request == request else { return }
                    image = decoded
                    loadedKey = key
                }
                return
            } catch ThumbnailPipelineError.queueFull {
                guard request.demand == .visible else { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            } catch MediaSourceError.thumbnailQueueFull {
                guard request.demand == .visible else { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            } catch {
                // Missing source thumbnails leave metadata and the placeholder available.
                return
            }
        }
    }
}

private struct ThumbnailRequest: Equatable {
    let asset: MediaAsset
    let sessionID: UUID?
    let reusableIdentity: String?
    let available: Bool
    let demand: ThumbnailDemand
}

import MediaModels
import SwiftUI

/// Metadata is requested only while this Info section is visible, never during library enumeration.
struct MediaInfoCameraView: View {
    let asset: MediaAsset
    @Environment(AppModel.self) private var model
    @State private var retry = 0
    @State private var loadedRequest: Request?
    @State private var state: LoadState = .loading

    private struct Request: Equatable {
        let asset: MediaAsset
        let sessionID: UUID?
        let ready: Bool
        let busy: Bool
        let retry: Int
    }

    private enum LoadState {
        case loading
        case loaded(PhotoCameraMetadata)
        case failed
    }

    private var request: Request {
        Request(asset: asset, sessionID: model.catalogSessionID,
                ready: model.deviceState == .ready && !model.isSample, busy: model.backup.isBusy, retry: retry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera").font(.headline)
            GroupBox {
                contents
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
        }
        .task(id: request) { await load(request) }
    }

    @ViewBuilder private var contents: some View {
        if !request.ready {
            message("Connect and unlock your iPhone to view camera details.")
        } else if request.busy {
            message("Camera details will load after the backup finishes.")
        } else if loadedRequest != request {
            loading
        } else {
            switch state {
            case .loading:
                loading
            case .loaded(let metadata):
                let fields = PhotoMetadataPresentation.fields(for: metadata)
                if fields.isEmpty {
                    message("Camera details aren’t available for this photo.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(fields) { field in
                            MediaInfoDetailRow(label: field.label, value: field.value)
                        }
                    }
                }
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    message("Couldn’t read camera details from your iPhone.")
                    Button("Try Again") { retry += 1 }
                        .controlSize(.small)
                }
            }
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            message("Reading camera details…")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading camera details")
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func load(_ request: Request) async {
        loadedRequest = request
        state = .loading
        guard request.ready, !request.busy, let sessionID = request.sessionID else { return }
        do {
            let metadata = try await model.photoMetadata(for: request.asset, sessionID: sessionID)
            try Task.checkCancellation()
            guard self.request == request else { return }
            state = .loaded(metadata)
        } catch is CancellationError {
            // A dismissed sheet or changed asset cannot receive this result.
        } catch {
            guard !Task.isCancelled, self.request == request else { return }
            state = .failed
        }
    }
}

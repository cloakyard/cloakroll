/// Shared ownership for successive browsers belonging to one app model. Retired thumbnail and
/// original calls retain their physical slots until completion, including across replacement sessions.
@MainActor
public final class DeviceCaptureContext {
    let thumbnailRequests = ThumbnailRequestCoordinator()
    let originalDownloads = OriginalDownloadCoordinator()
    let photoMetadataRequests = PhotoMetadataRequestCoordinator()

    public var thumbnailDiagnostics: ThumbnailRequestDiagnostics { thumbnailRequests.diagnostics }

    public init() {}
}

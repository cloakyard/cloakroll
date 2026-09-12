/// Shared ownership for successive browsers belonging to one app model. Retired thumbnail calls
/// keep their physical slots until completion even when a replacement browser opens a new session.
@MainActor
public final class DeviceCaptureContext {
    let thumbnailRequests = ThumbnailRequestCoordinator()

    public var thumbnailDiagnostics: ThumbnailRequestDiagnostics { thumbnailRequests.diagnostics }

    public init() {}
}

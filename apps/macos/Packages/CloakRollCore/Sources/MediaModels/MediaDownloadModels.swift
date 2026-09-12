import Foundation

/// Transport progress only. A completed byte count is not a verified backup result.
public struct DownloadProgress: Equatable, Sendable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64?

    public init(downloadedBytes: Int64, totalBytes: Int64?) {
        self.downloadedBytes = max(0, downloadedBytes)
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// A completed transport's candidate file. The backup engine must validate the path, source size,
/// file contents and destination publication before treating it as a verified original.
public struct DownloadedOriginal: Equatable, Sendable {
    public let url: URL
    public let expectedByteCount: Int64

    public init(url: URL, expectedByteCount: Int64) {
        self.url = url
        self.expectedByteCount = expectedByteCount
    }
}

public enum OriginalDownloadError: Error, Equatable, Sendable {
    case busy
    case invalidDestination
    case invalidFilename
    case missingResult
    case invalidResult
    case unexpectedAncillaryFiles
    case originalPresentationUnavailable
    case failed(domain: String, code: Int)
}

extension OriginalDownloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .busy: "The iPhone is still finishing another transfer. Try again when it stops."
        case .invalidDestination: "The backup folder is unavailable. Choose the folder again."
        case .invalidFilename, .invalidResult, .missingResult, .unexpectedAncillaryFiles:
            "The iPhone returned an unexpected file. The item has not been marked as backed up."
        case .originalPresentationUnavailable:
            "The iPhone isn’t providing the original format. Reconnect it and try again."
        case .failed:
            "The iPhone couldn’t finish copying the original. Reconnect and unlock it, then try again."
        }
    }
}

@MainActor
public protocol OriginalMediaDownloading: AnyObject, Sendable {
    /// The caller must retain destination access and staging until this method settles. After
    /// launch, cancellation or session retirement settles only when the real callback arrives.
    func downloadOriginal(
        resourceID: String, sessionID: UUID, to directory: URL, filename: String,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal
}

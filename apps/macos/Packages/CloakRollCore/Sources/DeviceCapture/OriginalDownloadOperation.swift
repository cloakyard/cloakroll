import Foundation
import ImageCaptureCore
import MediaModels
import OSLog

@MainActor
enum OriginalDownloadOperation {
    static func start(
        camera: ICCameraDevice, file: ICCameraFile, directory: URL, filename: String,
        receive: @escaping OriginalDownloadCoordinator.Callback
    ) -> OriginalDownloadHandle {
        let delegate = OriginalDownloadDelegate(
            file: ObjectIdentifier(file), directory: directory, expectedByteCount: Int64(file.fileSize), receive: receive
        )
        camera.requestDownloadFile(
            file, options: options(directory: directory, filename: filename), downloadDelegate: delegate,
            didDownloadSelector: #selector(OriginalDownloadDelegate.didDownloadFile(_:error:options:contextInfo:)), contextInfo: nil
        )
        return OriginalDownloadHandle(
            cancel: { camera.cancelDownload() },
            cleanup: { withExtendedLifetime((camera, file, delegate)) {} }
        )
    }

    static func options(directory: URL, filename: String) -> [ICDownloadOption: Any] {
        [
            .downloadsDirectoryURL: directory,
            .saveAsFilename: filename,
            .overwrite: false,
            .deleteAfterSuccessfulDownload: false,
            .sidecarFiles: false,
            .truncateAfterSuccessfulDownload: false
        ]
    }
}

enum OriginalDownloadPaths {
    static func isFilename(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
            !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    static func result(
        directory: URL, filename: String?, ancillaryFiles: [String], expectedByteCount: Int64
    ) -> Result<DownloadedOriginal, OriginalDownloadError> {
        guard let filename, !filename.isEmpty else { return .failure(.missingResult) }
        guard directory.isFileURL, isFilename(filename) else { return .failure(.invalidResult) }
        guard ancillaryFiles.isEmpty else { return .failure(.unexpectedAncillaryFiles) }
        return .success(DownloadedOriginal(
            url: directory.appendingPathComponent(filename, isDirectory: false), expectedByteCount: expectedByteCount
        ))
    }
}

/// Keeps framework callbacks separate from the camera session delegate. It forwards only values;
/// ownership and terminal-result ordering belong to the shared main-actor coordinator.
final class OriginalDownloadDelegate: NSObject, ICCameraDeviceDownloadDelegate {
    private let file: ObjectIdentifier
    private let directory: URL
    private let expectedByteCount: Int64
    private let receive: OriginalDownloadCoordinator.Callback
    private let logger = Logger(subsystem: "com.cloakroll.core", category: "OriginalDownloads")

    init(
        file: ObjectIdentifier, directory: URL, expectedByteCount: Int64,
        receive: @escaping OriginalDownloadCoordinator.Callback
    ) {
        self.file = file
        self.directory = directory
        self.expectedByteCount = expectedByteCount
        self.receive = receive
    }

    func didDownloadFile(
        _ file: ICCameraFile, error: (any Error)?, options: [String: Any], contextInfo: UnsafeMutableRawPointer?
    ) {
        guard ObjectIdentifier(file) == self.file else { return }
        if let error {
            let error = error as NSError
            logger.error("Original download error domain: \(error.domain, privacy: .public), code: \(error.code, privacy: .public)")
            receive(.completed(.failure(.failed(domain: error.domain, code: error.code))))
            return
        }
        let ancillary = options[ICDownloadOption.savedAncillaryFiles.rawValue]
        guard ancillary == nil || ancillary is [String] else {
            receive(.completed(.failure(.invalidResult)))
            return
        }
        receive(.completed(OriginalDownloadPaths.result(
            directory: directory, filename: options[ICDownloadOption.savedFilename.rawValue] as? String,
            ancillaryFiles: ancillary as? [String] ?? [], expectedByteCount: expectedByteCount
        )))
    }

    func didReceiveDownloadProgress(for file: ICCameraFile, downloadedBytes: off_t, maxBytes: off_t) {
        guard ObjectIdentifier(file) == self.file else { return }
        receive(.progress(DownloadProgress(downloadedBytes: Int64(downloadedBytes), totalBytes: Int64(maxBytes))))
    }
}

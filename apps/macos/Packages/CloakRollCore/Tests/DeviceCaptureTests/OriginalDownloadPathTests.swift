import Foundation
import ImageCaptureCore
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Original download destination boundaries")
struct OriginalDownloadPathTests {
    @Test(arguments: ["", ".", "..", "../original.HEIC", "/outside.HEIC", "folder/original.HEIC", "a\\b", "a\0b"])
    func unsafeNamesAreRejected(_ filename: String) {
        #expect(!OriginalDownloadPaths.isFilename(filename))
    }

    @Test func candidateUsesTheActualReturnedNameAndPreservesUnknownSize() throws {
        let directory = URL(fileURLWithPath: "/unused-staging", isDirectory: true)
        let result = try OriginalDownloadPaths.result(
            directory: directory, filename: "actual name.HEIC", ancillaryFiles: [], expectedByteCount: 0
        ).get()
        #expect(result.url == directory.appendingPathComponent("actual name.HEIC"))
        #expect(result.expectedByteCount == 0)
    }

    @Test func missingOrUnexpectedResultsAreNotSuccessfulOriginals() {
        let directory = URL(fileURLWithPath: "/unused-staging", isDirectory: true)
        #expect(OriginalDownloadPaths.result(
            directory: directory, filename: nil, ancillaryFiles: [], expectedByteCount: 100
        ) == .failure(.missingResult))
        #expect(OriginalDownloadPaths.result(
            directory: directory, filename: "../elsewhere", ancillaryFiles: [], expectedByteCount: 100
        ) == .failure(.invalidResult))
        #expect(OriginalDownloadPaths.result(
            directory: directory, filename: "original.HEIC", ancillaryFiles: ["unexpected.MOV"], expectedByteCount: 100
        ) == .failure(.unexpectedAncillaryFiles))
        #expect(OriginalDownloadPaths.result(
            directory: URL(string: "https://example.com")!, filename: "original.HEIC", ancillaryFiles: [], expectedByteCount: 100
        ) == .failure(.invalidResult))
    }

    @Test @MainActor func optionsDisableDeletionTruncationSidecarsAndOverwrite() {
        let directory = URL(fileURLWithPath: "/unused-staging", isDirectory: true)
        let options = OriginalDownloadOperation.options(directory: directory, filename: "original.HEIC")
        #expect(options[.downloadsDirectoryURL] as? URL == directory)
        #expect(options[.saveAsFilename] as? String == "original.HEIC")
        #expect(options[.overwrite] as? Bool == false)
        #expect(options[.deleteAfterSuccessfulDownload] as? Bool == false)
        #expect(options[.sidecarFiles] as? Bool == false)
        #expect(options[.truncateAfterSuccessfulDownload] as? Bool == false)
    }

    @Test func unknownOrNegativeProgressNeverInventsACompletionFraction() {
        #expect(DownloadProgress(downloadedBytes: -1, totalBytes: -1) == DownloadProgress(downloadedBytes: 0, totalBytes: nil))
        #expect(DownloadProgress(downloadedBytes: 10, totalBytes: 0).totalBytes == nil)
    }

    @Test @MainActor func adapterRejectsUnsafeDestinationsBeforeAnySessionOrDeviceRequest() async {
        let service = DeviceBrowserService()
        await #expect(throws: OriginalDownloadError.invalidDestination) {
            try await service.downloadOriginal(
                resourceID: "unused", sessionID: UUID(), to: URL(string: "https://example.com")!,
                filename: "original.HEIC", progress: { _ in }
            )
        }
        await #expect(throws: OriginalDownloadError.invalidFilename) {
            try await service.downloadOriginal(
                resourceID: "unused", sessionID: UUID(), to: URL(fileURLWithPath: "/unused-staging"),
                filename: "../outside.HEIC", progress: { _ in }
            )
        }
    }

    @Test @MainActor func adapterWithoutAReadySessionNeverLaunchesAnOriginalRequest() async {
        let service = DeviceBrowserService()
        await #expect(throws: MediaSourceError.staleSession) {
            try await service.downloadOriginal(
                resourceID: "unused", sessionID: UUID(), to: URL(fileURLWithPath: "/unused-staging"),
                filename: "original.HEIC", progress: { _ in }
            )
        }
    }
}

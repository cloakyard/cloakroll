import Foundation
import ImageCaptureCore
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Original download Objective-C delegate dispatch")
struct OriginalDownloadDelegateTests {
    @Test func optionalProtocolWitnessUsesTheSDKSelectorAndForwardsFullWidthByteCounts() {
        let file = ICCameraFile()
        let recorder = OriginalDelegateProgressRecorder()
        let delegate = makeDelegate(file: file, recorder: recorder)
        let expectedSelector = NSSelectorFromString("didReceiveDownloadProgressForFile:downloadedBytes:maxBytes:")
        let protocolSelector = #selector(ICCameraDeviceDownloadDelegate.didReceiveDownloadProgress(for:downloadedBytes:maxBytes:))
        let implementationSelector = #selector(OriginalDownloadDelegate.didReceiveDownloadProgress(for:downloadedBytes:maxBytes:))
        #expect(protocolSelector == expectedSelector)
        #expect(implementationSelector == expectedSelector)
        #expect(delegate.responds(to: expectedSelector))

        // Exercise Objective-C optional-protocol dispatch, not a direct concrete Swift call.
        let protocolDelegate: any ICCameraDeviceDownloadDelegate = delegate
        protocolDelegate.didReceiveDownloadProgress?(for: file, downloadedBytes: 5_000_000_000, maxBytes: 6_000_000_000)
        #expect(recorder.values == [DownloadProgress(downloadedBytes: 5_000_000_000, totalBytes: 6_000_000_000)])
    }

    @Test func progressForAnotherFrameworkFileIsIgnored() {
        let file = ICCameraFile()
        let otherFile = ICCameraFile()
        let recorder = OriginalDelegateProgressRecorder()
        let delegate: any ICCameraDeviceDownloadDelegate = makeDelegate(file: file, recorder: recorder)
        delegate.didReceiveDownloadProgress?(for: otherFile, downloadedBytes: 50, maxBytes: 100)
        #expect(recorder.values.isEmpty)
        delegate.didReceiveDownloadProgress?(for: file, downloadedBytes: 75, maxBytes: 100)
        #expect(recorder.values == [DownloadProgress(downloadedBytes: 75, totalBytes: 100)])
    }

    private func makeDelegate(file: ICCameraFile, recorder: OriginalDelegateProgressRecorder) -> OriginalDownloadDelegate {
        OriginalDownloadDelegate(
            file: ObjectIdentifier(file), directory: URL(fileURLWithPath: "/unused-staging"), expectedByteCount: 100
        ) { event in
            if case .progress(let value) = event { recorder.append(value) }
        }
    }
}

private final class OriginalDelegateProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DownloadProgress] = []

    var values: [DownloadProgress] { lock.withLock { storage } }

    func append(_ value: DownloadProgress) { lock.withLock { storage.append(value) } }
}

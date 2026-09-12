import Foundation
import Testing
@testable import DeviceCapture

@Suite("Device error normalization")
struct CaptureErrorTests {
    @Test("A nil framework error does not become a failure event")
    func nilErrorDoesNotInventFailure() {
        #expect(CameraCallback.encounteredError(nil) == nil)
    }

    @Test("Framework error domain and code survive normalization separately from private detail")
    func errorEvidenceIsPreserved() throws {
        let source = NSError(
            domain: "com.apple.ImageCaptureCore", code: -21343,
            userInfo: [NSLocalizedDescriptionKey: "Private device-specific description"]
        )
        let callback = try #require(CameraCallback.encounteredError(source))
        guard case .failed(let error) = callback else {
            Issue.record("Expected a normalized failure")
            return
        }
        #expect(error.domain == source.domain)
        #expect(error.code == source.code)
        #expect(error.message == "Private device-specific description")
    }
}

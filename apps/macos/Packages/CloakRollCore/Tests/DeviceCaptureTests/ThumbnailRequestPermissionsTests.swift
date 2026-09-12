import ImageCaptureCore
import Testing
@testable import DeviceCapture

@Suite("Explicit thumbnail request permissions")
@MainActor
struct ThumbnailRequestPermissionsTests {
    @Test("Enumeration alone does not authorize thumbnail I/O; only explicit pending requests do")
    func explicitRequestsOnly() {
        let permissions = ThumbnailRequestPermissions()
        let delegate = CaptureCameraDelegate(shouldGetThumbnail: { permissions.contains($0) }) { _ in }
        let camera = ICCameraDevice()
        let visible = CatalogTestFile(name: "VISIBLE.JPG")
        let other = CatalogTestFile(name: "OTHER.JPG")
        #expect(!delegate.cameraDevice(camera, shouldGetThumbnailOf: visible))
        permissions.insert(ObjectIdentifier(visible))
        #expect(delegate.cameraDevice(camera, shouldGetThumbnailOf: visible))
        #expect(!delegate.cameraDevice(camera, shouldGetThumbnailOf: other))
        permissions.remove(ObjectIdentifier(visible))
        #expect(!delegate.cameraDevice(camera, shouldGetThumbnailOf: visible))
        #expect(!delegate.cameraDevice(camera, shouldGetMetadataOf: visible))
    }

    @Test("Overlapping requests for the same item stay allowed until both callbacks finish")
    func overlappingRequests() {
        let permissions = ThumbnailRequestPermissions()
        let file = CatalogTestFile(name: "ONE.JPG")
        let identifier = ObjectIdentifier(file)
        permissions.insert(identifier)
        permissions.insert(identifier)
        permissions.remove(identifier)
        #expect(permissions.contains(identifier))
        permissions.remove(identifier)
        #expect(!permissions.contains(identifier))
        permissions.remove(identifier)
        #expect(!permissions.contains(identifier))
    }
}

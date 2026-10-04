import ImageCaptureCore
import Testing
@testable import DeviceCapture

@Suite("Explicit thumbnail request permissions")
@MainActor
struct ThumbnailRequestPermissionsTests {
    @Test("Enumeration alone does not authorize thumbnail I/O; only explicit pending requests do")
    func explicitRequestsOnly() {
        let permissions = CaptureRequestPermissions()
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
        let permissions = CaptureRequestPermissions()
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

    @Test("Camera metadata is denied by default and authorized independently of thumbnail requests")
    func metadataRequiresExplicitRequest() {
        let permissions = CaptureRequestPermissions()
        let delegate = CaptureCameraDelegate(shouldGetMetadata: { permissions.contains($0) }) { _ in }
        let camera = ICCameraDevice()
        let requested = CatalogTestFile(name: "REQUESTED.HEIC")
        let other = CatalogTestFile(name: "OTHER.HEIC")
        #expect(!delegate.cameraDevice(camera, shouldGetMetadataOf: requested))
        permissions.insert(ObjectIdentifier(requested))
        #expect(delegate.cameraDevice(camera, shouldGetMetadataOf: requested))
        #expect(!delegate.cameraDevice(camera, shouldGetMetadataOf: other))
        #expect(!delegate.cameraDevice(camera, shouldGetThumbnailOf: requested))
        permissions.remove(ObjectIdentifier(requested))
        #expect(!delegate.cameraDevice(camera, shouldGetMetadataOf: requested))
    }
}

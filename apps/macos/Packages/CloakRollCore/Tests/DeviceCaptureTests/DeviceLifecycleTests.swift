import Foundation
import ImageCaptureCore
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Device identity and classification")
struct DeviceIdentityTests {
    private let usbTransport = ICDeviceTransport.transportTypeUSB.rawValue

    @Test("Persistent identity takes precedence over serial and framework UUID")
    func persistentIdentityHasPriority() {
        let identity = DeviceIdentityResolver.resolve(
            persistentID: "persistent-phone", serialNumber: "serial-phone", uuid: "framework-phone", sessionID: UUID()
        )

        #expect(identity.kind == .persistent)
        #expect(identity.value == "persistent-phone")
        #expect(identity.isPersistent)
    }

    @Test("Missing and blank identifiers fall back without inventing persistent identity")
    func identifierFallbacks() {
        let serial = DeviceIdentityResolver.resolve(
            persistentID: " \n\t", serialNumber: "serial-phone", uuid: "framework-phone", sessionID: UUID()
        )
        let frameworkUUID = DeviceIdentityResolver.resolve(
            persistentID: nil, serialNumber: "", uuid: "framework-phone", sessionID: UUID()
        )

        #expect(serial.kind == .serialNumber)
        #expect(serial.value == "serial-phone")
        #expect(serial.isPersistent)
        #expect(frameworkUUID.kind == .uuid)
        #expect(frameworkUUID.value == "framework-phone")
        #expect(frameworkUUID.isPersistent)
    }

    @Test("The same source identity survives a new session token")
    func stableIdentityDoesNotDependOnSession() {
        let first = DeviceIdentityResolver.resolve(
            persistentID: "phone-a", serialNumber: nil, uuid: nil, sessionID: UUID()
        )
        let reconnect = DeviceIdentityResolver.resolve(
            persistentID: "phone-a", serialNumber: nil, uuid: nil, sessionID: UUID()
        )
        let otherPhone = DeviceIdentityResolver.resolve(
            persistentID: "phone-b", serialNumber: nil, uuid: nil, sessionID: UUID()
        )

        #expect(first == reconnect)
        #expect(first != otherPhone)
    }

    @Test("Missing device identifiers are isolated to the current session")
    func sessionOnlyIdentityCannotMatchAnotherConnection() {
        let session = UUID()
        let first = DeviceIdentityResolver.resolve(
            persistentID: nil, serialNumber: nil, uuid: nil, sessionID: session
        )
        let repeatInSession = DeviceIdentityResolver.resolve(
            persistentID: "", serialNumber: "\n", uuid: " \t", sessionID: session
        )
        let reconnect = DeviceIdentityResolver.resolve(
            persistentID: nil, serialNumber: nil, uuid: nil, sessionID: UUID()
        )

        #expect(first.kind == .sessionOnly)
        #expect(!first.value.isEmpty)
        #expect(!first.isPersistent)
        #expect(first == repeatInSession)
        #expect(first != reconnect)
    }

    @Test("Identity kind remains part of identity when raw values coincide")
    func differentIdentityEvidenceDoesNotCollide() {
        let persistent = DeviceIdentity(kind: .persistent, value: "shared-value")
        let serial = DeviceIdentity(kind: .serialNumber, value: "shared-value")
        let frameworkUUID = DeviceIdentity(kind: .uuid, value: "shared-value")

        #expect(persistent != serial)
        #expect(serial != frameworkUUID)
        #expect(persistent != frameworkUUID)
    }

    @Test("Known Apple mobile products on USB are supported", arguments: ["iPhone", "iPad", "iPod"])
    func supportedAppleMobileProducts(productKind: String) {
        #expect(DeviceClassification.isSupported(productKind: productKind, usbVendorID: 0x05ac, transportType: usbTransport))
    }

    @Test("An Apple vendor ID without a known mobile product is insufficient", arguments: ["Camera", "Mac", ""])
    func unrelatedAppleProductsAreNotPhones(productKind: String) {
        #expect(!DeviceClassification.isSupported(productKind: productKind, usbVendorID: 0x05ac, transportType: usbTransport))
    }

    @Test("Unknown, non-Apple and remote devices are not silently classified as supported")
    func unsupportedDeviceEvidence() {
        #expect(!DeviceClassification.isSupported(productKind: nil, usbVendorID: 0x05ac, transportType: usbTransport))
        #expect(!DeviceClassification.isSupported(productKind: "iPhone", usbVendorID: 0x04b0, transportType: usbTransport))
        #expect(!DeviceClassification.isSupported(productKind: "iPhone", usbVendorID: 0x05ac, transportType: "TCP/IP"))
        #expect(!DeviceClassification.isSupported(productKind: "iPhone", usbVendorID: 0x05ac, transportType: nil))
    }
}

@Suite("Device session lifecycle")
struct DeviceLifecycleTests {
    private func device(_ value: String = "phone-a") -> ConnectedDevice {
        ConnectedDevice(identity: DeviceIdentity(kind: .persistent, value: value), name: "My phone", productKind: "iPhone")
    }

    @Test("Session opening is distinct from complete catalog readiness")
    func openWaitsForReady() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        let phone = device()

        #expect(lifecycle.connection.state == .disconnected)
        #expect(lifecycle.connection.device == nil)
        #expect(lifecycle.activeToken == nil)

        lifecycle.begin(device: phone, token: token)
        #expect(lifecycle.connection.state == .opening)
        #expect(lifecycle.connection.device == phone)
        #expect(lifecycle.activeToken == token)

        lifecycle.opened(token: token, errorMessage: nil, restricted: false)
        #expect(lifecycle.connection.state == .opening)

        lifecycle.ready(token: token)
        #expect(lifecycle.connection.state == .ready)
        #expect(lifecycle.connection.device == phone)
    }

    @Test("Removing access restrictions without a ready event remains opening")
    func unlockingDoesNotInventReadiness() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        lifecycle.begin(device: device(), token: token)
        lifecycle.opened(token: token, errorMessage: nil, restricted: true)
        #expect(lifecycle.connection.state == .restricted)

        lifecycle.accessChanged(token: token, restricted: false)
        #expect(lifecycle.connection.state == .opening)

        lifecycle.ready(token: token)
        #expect(lifecycle.connection.state == .ready)
    }

    @Test("A ready event during restriction is remembered until access is restored")
    func readinessDuringRestrictionRequiresExplicitAccessRecovery() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        lifecycle.begin(device: device(), token: token)
        lifecycle.opened(token: token, errorMessage: nil, restricted: true)

        lifecycle.ready(token: token)
        #expect(lifecycle.connection.state == .restricted)

        lifecycle.accessChanged(token: token, restricted: false)
        #expect(lifecycle.connection.state == .ready)
    }

    @Test("Restricted session errors preserve the active device and permit unlock recovery")
    func restrictedSessionErrorsRemainRecoverable() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        let phone = device()
        lifecycle.begin(device: phone, token: token)
        lifecycle.accessChanged(token: token, restricted: true)

        lifecycle.opened(token: token, errorMessage: "The device is restricted.", restricted: true)
        #expect(lifecycle.connection.state == .restricted)
        #expect(lifecycle.connection.device == phone)
        #expect(lifecycle.activeToken == token)

        lifecycle.failed(token: token, message: "Session access failed while restricted.")
        #expect(lifecycle.connection.state == .restricted)
        #expect(lifecycle.connection.device == phone)
        #expect(lifecycle.activeToken == token)

        lifecycle.ready(token: token)
        #expect(lifecycle.connection.state == .restricted)
        lifecycle.accessChanged(token: token, restricted: false)
        #expect(lifecycle.connection.state == .ready)
        #expect(lifecycle.connection.device == phone)
        #expect(lifecycle.activeToken == token)
    }

    @Test("Duplicate restriction callbacks do not discard readiness received during restriction")
    func repeatedRestrictionPreservesNewReadiness() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        lifecycle.begin(device: device(), token: token)
        lifecycle.opened(token: token, errorMessage: nil, restricted: false)
        lifecycle.ready(token: token)
        lifecycle.accessChanged(token: token, restricted: true)

        lifecycle.ready(token: token)
        lifecycle.accessChanged(token: token, restricted: true)
        lifecycle.opened(token: token, errorMessage: "The device remains restricted.", restricted: true)
        #expect(lifecycle.connection.state == .restricted)

        lifecycle.accessChanged(token: token, restricted: false)
        #expect(lifecycle.connection.state == .ready)
    }

    @Test("An older session cannot restore access to the current restricted device")
    func staleUnlockCannotRecoverRestrictedSession() {
        var lifecycle = DeviceLifecycle()
        let staleToken = UUID()
        let currentToken = UUID()
        let currentPhone = device("phone-b")
        lifecycle.begin(device: device(), token: staleToken)
        lifecycle.begin(device: currentPhone, token: currentToken)
        lifecycle.opened(token: currentToken, errorMessage: "Access is restricted.", restricted: true)
        lifecycle.ready(token: currentToken)
        #expect(lifecycle.connection.state == .restricted)

        lifecycle.accessChanged(token: staleToken, restricted: false)
        #expect(lifecycle.connection.state == .restricted)
        lifecycle.opened(token: staleToken, errorMessage: nil, restricted: false)
        #expect(lifecycle.connection.state == .restricted)
        lifecycle.ready(token: staleToken)
        #expect(lifecycle.connection.state == .restricted)
        #expect(lifecycle.connection.device == currentPhone)
        #expect(lifecycle.activeToken == currentToken)

        lifecycle.accessChanged(token: currentToken, restricted: false)
        #expect(lifecycle.connection.state == .ready)
    }

    @Test("A new access restriction revokes ready state")
    func readyDeviceCanBecomeRestricted() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        lifecycle.begin(device: device(), token: token)
        lifecycle.opened(token: token, errorMessage: nil, restricted: false)
        lifecycle.ready(token: token)

        lifecycle.accessChanged(token: token, restricted: true)
        #expect(lifecycle.connection.state == .restricted)

        lifecycle.accessChanged(token: token, restricted: false)
        #expect(lifecycle.connection.state == .opening)
    }

    @Test("A session error reports unavailable rather than guessing lock or trust status")
    func sessionErrorIsUnavailable() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        let phone = device()
        lifecycle.begin(device: phone, token: token)

        lifecycle.opened(token: token, errorMessage: "Session could not open.", restricted: false)

        #expect(lifecycle.connection.state == .unavailable)
        #expect(lifecycle.connection.device == phone)
        #expect(lifecycle.connection.message == "Session could not open.")

        lifecycle.removed(token: token)
        #expect(lifecycle.connection.state == .disconnected)
        #expect(lifecycle.connection.device == nil)
        #expect(lifecycle.activeToken == nil)
    }

    @Test("Failure cannot be reversed by late success callbacks; a new session can recover")
    func errorRequiresANewSession() {
        var lifecycle = DeviceLifecycle()
        let failedToken = UUID()
        let retryToken = UUID()
        let phone = device()
        lifecycle.begin(device: phone, token: failedToken)
        lifecycle.opened(token: failedToken, errorMessage: nil, restricted: false)
        lifecycle.failed(token: failedToken, message: "Connection interrupted.")
        #expect(lifecycle.connection.state == .unavailable)

        lifecycle.ready(token: failedToken)
        #expect(lifecycle.connection.state == .unavailable)
        lifecycle.accessChanged(token: failedToken, restricted: false)
        #expect(lifecycle.connection.state == .unavailable)
        lifecycle.opened(token: failedToken, errorMessage: nil, restricted: false)
        #expect(lifecycle.connection.state == .unavailable)

        lifecycle.begin(device: phone, token: retryToken)
        #expect(lifecycle.connection.state == .opening)
        #expect(lifecycle.activeToken == retryToken)
        lifecycle.opened(token: retryToken, errorMessage: nil, restricted: false)
        lifecycle.ready(token: retryToken)
        #expect(lifecycle.connection.state == .ready)
    }

    @Test("Callbacks from a replaced session cannot change the current device")
    func staleEventsCannotAffectNewConnection() {
        var lifecycle = DeviceLifecycle()
        let staleToken = UUID()
        let currentToken = UUID()
        let currentPhone = device("phone-b")
        lifecycle.begin(device: device(), token: staleToken)
        lifecycle.begin(device: currentPhone, token: currentToken)
        lifecycle.opened(token: currentToken, errorMessage: nil, restricted: false)
        lifecycle.ready(token: currentToken)

        lifecycle.opened(token: staleToken, errorMessage: "Old session failure.", restricted: false)
        #expect(lifecycle.connection.state == .ready)
        lifecycle.accessChanged(token: staleToken, restricted: true)
        #expect(lifecycle.connection.state == .ready)
        lifecycle.failed(token: staleToken, message: "Old device disappeared.")
        #expect(lifecycle.connection.state == .ready)
        lifecycle.removed(token: staleToken)
        #expect(lifecycle.connection.state == .ready)
        #expect(lifecycle.connection.device == currentPhone)
        #expect(lifecycle.activeToken == currentToken)
    }

    @Test("Old ready callbacks do not complete a new session")
    func staleReadinessDoesNotCompleteNewSession() {
        var lifecycle = DeviceLifecycle()
        let staleToken = UUID()
        let currentToken = UUID()
        lifecycle.begin(device: device(), token: staleToken)
        lifecycle.begin(device: device(), token: currentToken)

        lifecycle.ready(token: staleToken)

        #expect(lifecycle.connection.state == .opening)
        #expect(lifecycle.activeToken == currentToken)
    }

    @Test("Disconnect invalidates callbacks from the removed device")
    func removalInvalidatesSession() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        lifecycle.begin(device: device(), token: token)
        lifecycle.opened(token: token, errorMessage: nil, restricted: false)
        lifecycle.ready(token: token)

        lifecycle.removed(token: token)
        #expect(lifecycle.connection.state == .disconnected)
        #expect(lifecycle.connection.device == nil)
        #expect(lifecycle.activeToken == nil)

        lifecycle.ready(token: token)
        lifecycle.opened(token: token, errorMessage: nil, restricted: false)
        lifecycle.accessChanged(token: token, restricted: true)
        lifecycle.failed(token: token, message: "Late failure.")
        #expect(lifecycle.connection.state == .disconnected)
        #expect(lifecycle.connection.device == nil)
    }

    @Test("Stopping discovery clears state and rejects pending session callbacks")
    func resetInvalidatesPendingOpen() {
        var lifecycle = DeviceLifecycle()
        let token = UUID()
        lifecycle.begin(device: device(), token: token)

        lifecycle.reset()
        lifecycle.opened(token: token, errorMessage: nil, restricted: false)
        lifecycle.ready(token: token)

        #expect(lifecycle.connection.state == .disconnected)
        #expect(lifecycle.connection.device == nil)
        #expect(lifecycle.activeToken == nil)
    }
}

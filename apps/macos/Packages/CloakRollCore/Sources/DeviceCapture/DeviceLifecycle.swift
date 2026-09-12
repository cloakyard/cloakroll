import Foundation
import MediaModels

/// Pure connection reducer. Tokens keep callbacks from prior sessions from changing current state.
struct DeviceLifecycle {
    private(set) var connection = DeviceConnection(state: .disconnected)
    private(set) var activeToken: UUID?
    private var isReady = false
    private var isRestricted = false

    mutating func begin(device: ConnectedDevice, token: UUID) {
        activeToken = token
        isReady = false
        isRestricted = false
        connection = DeviceConnection(device: device, state: .opening)
    }

    mutating func opened(token: UUID, errorMessage: String?, restricted: Bool) {
        guard accepts(token) else { return }
        accessChanged(token: token, restricted: restricted)
        if let errorMessage {
            failed(token: token, message: errorMessage)
        } else {
            updateAvailability()
        }
    }

    mutating func accessChanged(token: UUID, restricted: Bool) {
        guard accepts(token) else { return }
        if restricted && !isRestricted { isReady = false }
        isRestricted = restricted
        updateAvailability()
    }

    mutating func ready(token: UUID) {
        guard accepts(token) else { return }
        isReady = true
        updateAvailability()
    }

    mutating func failed(token: UUID, message: String) {
        guard accepts(token) else { return }
        // A trusted/unlocked phone can recover within this same framework session. Keep the
        // restriction visible and require both readiness and removal of that restriction.
        let state: DeviceConnectionState = isRestricted ? .restricted : .unavailable
        connection = DeviceConnection(device: connection.device, state: state, message: message)
    }

    mutating func closed(token: UUID, message: String) {
        guard activeToken == token else { return }
        // A closed session no longer owns usable camera handles. Unlock callbacks from it must
        // not revive readiness; retry opens a new session and a fresh resource namespace.
        connection = DeviceConnection(device: connection.device, state: .unavailable, message: message)
    }

    mutating func removed(token: UUID) {
        guard activeToken == token else { return }
        reset()
    }

    mutating func reset() {
        activeToken = nil
        isReady = false
        isRestricted = false
        connection = DeviceConnection(state: .disconnected)
    }

    private func accepts(_ token: UUID) -> Bool {
        activeToken == token && connection.state != .unavailable
    }

    private mutating func updateAvailability() {
        let state: DeviceConnectionState = isRestricted ? .restricted : (isReady ? .ready : .opening)
        connection = DeviceConnection(device: connection.device, state: state)
    }
}

import Foundation

/// Keep this owner alive until the final physical file operation completes, including cancellation.
/// A lock makes release/deinit safe when ownership crosses the transfer actor boundary.
final class DestinationLease: @unchecked Sendable {
    let url: URL
    let destinationID: UUID
    private let lock = NSLock()
    private var relinquish: (@Sendable () -> Void)?

    init(url: URL, destinationID: UUID, relinquish: (@Sendable () -> Void)?) {
        self.url = url
        self.destinationID = destinationID
        self.relinquish = relinquish
    }

    func release() {
        let action = lock.withLock {
            let action = relinquish
            relinquish = nil
            return action
        }
        action?()
    }

    deinit { release() }
}

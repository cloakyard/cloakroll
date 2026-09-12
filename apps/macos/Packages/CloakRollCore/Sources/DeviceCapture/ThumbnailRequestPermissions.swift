import Foundation

/// The synchronous framework delegate can run outside the actor. It sees only object identities,
/// never reads camera properties, and allows only explicit requests awaiting their real callback.
final class ThumbnailRequestPermissions: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [ObjectIdentifier: Int] = [:]

    func insert(_ identifier: ObjectIdentifier) {
        lock.withLock { counts[identifier, default: 0] += 1 }
    }

    func remove(_ identifier: ObjectIdentifier) {
        lock.withLock {
            guard let count = counts[identifier] else { return }
            counts[identifier] = count > 1 ? count - 1 : nil
        }
    }

    func contains(_ identifier: ObjectIdentifier) -> Bool {
        lock.withLock { counts[identifier] != nil }
    }
}

/// Cancellation can arrive on any executor, including before the actor enqueues the operation.
final class ThumbnailCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}

import Foundation
import MediaModels

/// Retains framework objects only on their owning actor. Neither names nor PTP handles identify
/// an object, and every new session starts a fresh namespace even for the same physical phone.
@MainActor
final class CaptureObjectRegistry<Object: AnyObject> {
    private(set) var sessionID: UUID?
    private var nextID: UInt64 = 0
    private var identities: [ObjectIdentifier: String] = [:]
    private var objects: [String: Object] = [:]

    func begin(sessionID: UUID) {
        clear()
        self.sessionID = sessionID
    }

    func identifier(for object: Object) -> String {
        guard let sessionID else { preconditionFailure("A camera registry requires an active session") }
        let key = ObjectIdentifier(object)
        if let existing = identities[key] { return existing }
        nextID += 1
        let identifier = "\(sessionID.uuidString):\(nextID)"
        identities[key] = identifier
        objects[identifier] = object
        return identifier
    }

    func existingIdentifier(for object: Object) -> String? {
        identities[ObjectIdentifier(object)]
    }

    func object(for identifier: String, sessionID: UUID) throws -> Object {
        guard self.sessionID == sessionID else { throw MediaSourceError.staleSession }
        guard let object = objects[identifier] else { throw MediaSourceError.missingResource }
        return object
    }

    func remove(_ identifier: String) {
        guard let object = objects.removeValue(forKey: identifier) else { return }
        identities.removeValue(forKey: ObjectIdentifier(object))
    }

    func clear() {
        sessionID = nil
        nextID = 0
        identities.removeAll()
        objects.removeAll()
    }
}

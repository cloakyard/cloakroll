import Foundation
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Camera handle registry")
@MainActor
struct CaptureObjectRegistryTests {
    @Test("Object identity stays stable within a session and never collapses equal filenames")
    func objectIdentity() throws {
        let registry = CaptureObjectRegistry<CatalogTestFile>()
        let session = UUID()
        registry.begin(sessionID: session)
        let first = CatalogTestFile(name: "SAME.JPG")
        let second = CatalogTestFile(name: "SAME.JPG")
        let firstID = registry.identifier(for: first)
        let secondID = registry.identifier(for: second)
        #expect(firstID != secondID)
        #expect(registry.identifier(for: first) == firstID)
        #expect(try registry.object(for: firstID, sessionID: session) === first)
    }

    @Test("Retired sessions and removed handles cannot be looked up or reused")
    func retirement() throws {
        let registry = CaptureObjectRegistry<CatalogTestFile>()
        let firstSession = UUID()
        let secondSession = UUID()
        let file = CatalogTestFile(name: "ONE.JPG")
        registry.begin(sessionID: firstSession)
        let firstID = registry.identifier(for: file)
        registry.begin(sessionID: secondSession)
        let secondID = registry.identifier(for: file)
        #expect(firstID != secondID)
        #expect(throws: MediaSourceError.staleSession) {
            try registry.object(for: firstID, sessionID: firstSession)
        }
        #expect(throws: MediaSourceError.missingResource) {
            try registry.object(for: firstID, sessionID: secondSession)
        }
        registry.remove(secondID)
        #expect(registry.existingIdentifier(for: file) == nil)
        #expect(registry.identifier(for: file) != secondID)
    }
}

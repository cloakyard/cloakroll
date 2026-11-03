import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Saved-original action lifetime", .timeLimit(.minutes(1)))
@MainActor
struct SavedOriginalActionsTests {
    @Test func previewRetainsAccessUntilItsLastPresentationOwnerReleasesIt() async throws {
        let fixture = try BackupControllerFixture()
        let actions = SavedOriginalActions(resolve: { folder, record in folder.appendingPathComponent(record.filename) })
        await actions.open(record(), folder: fixture.controller.destination, previewing: true).value
        #expect(actions.preview != nil && !actions.isOpening)
        #expect(fixture.scope.counts.active == 1)
        var rendererOwner = actions.preview
        actions.cancel()
        #expect(actions.preview == nil && fixture.scope.counts.active == 1)
        #expect(rendererOwner?.url.lastPathComponent == "IMG.HEIC")
        rendererOwner = nil
        #expect(fixture.scope.counts.active == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func cancellationSuppressesLatePreviewRevealAndErrors(previewing: Bool, fails: Bool) async throws {
        let fixture = try BackupControllerFixture()
        let reads = SavedActionReads()
        var revealed: [URL] = []
        let actions = SavedOriginalActions(resolve: { try await reads.resolve($0, record: $1) }, reveal: { revealed.append($0) })
        let pending = actions.open(record(), folder: fixture.controller.destination, previewing: previewing)
        await reads.waitForStart("still")
        actions.cancel()
        #expect(fixture.scope.counts.active == 1) // The physical callback still owns its scope.
        await reads.finish("still", fails: fails)
        await pending.value
        #expect(actions.preview == nil && actions.errorMessage == nil && revealed.isEmpty && !actions.isOpening)
        #expect(fixture.scope.counts.active == 0)
    }

    @Test func replacementIgnoresTheOldCallbackAndUsesTheNewFolder() async throws {
        let first = try BackupControllerFixture()
        let second = try BackupControllerFixture()
        let reads = SavedActionReads()
        let actions = SavedOriginalActions(resolve: { try await reads.resolve($0, record: $1) })
        let old = actions.open(record(), folder: first.controller.destination, previewing: true)
        await reads.waitForStart("still")
        let current = actions.open(record(companion: true), folder: second.controller.destination, previewing: true)
        await reads.waitForStart("motion")
        await reads.finish("still", fails: true)
        await old.value
        #expect(actions.isOpening && actions.errorMessage == nil && actions.preview == nil)
        #expect(first.scope.counts.active == 0 && second.scope.counts.active == 1)
        await reads.finish("motion")
        await current.value
        #expect(actions.preview?.url == second.folder.appendingPathComponent("IMG.MOV"))
        actions.cancel()
        #expect(second.scope.counts.active == 0)
    }

    @Test func currentReadFailureReleasesAccessAndCanBeRetried() async throws {
        let fixture = try BackupControllerFixture()
        let reads = SavedActionReads()
        var revealed: [URL] = []
        let actions = SavedOriginalActions(resolve: { try await reads.resolve($0, record: $1) }, reveal: { revealed.append($0) })
        let failed = actions.open(record(), folder: fixture.controller.destination, previewing: true)
        await reads.waitForStart("still")
        await reads.finish("still", fails: true)
        await failed.value
        #expect(actions.errorMessage != nil && fixture.scope.counts.active == 0)
        let retry = actions.open(record(), folder: fixture.controller.destination, previewing: false)
        await reads.waitForStart("still")
        await reads.finish("still")
        await retry.value
        #expect(actions.errorMessage == nil && revealed == [fixture.folder.appendingPathComponent("IMG.HEIC")])
        #expect(fixture.scope.counts.active == 0)
    }

    private func record(companion: Bool = false) -> VerifiedBackupResource {
        let asset = BackupLibraryFixture.asset(companion: companion)
        return BackupLibraryFixture.record(asset, resource: asset.resources.last!, sessionID: UUID())
    }
}

private actor SavedActionReads {
    private var pending: [String: CheckedContinuation<Void, Error>] = [:]
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]

    func resolve(_ folder: URL, record: VerifiedBackupResource) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            pending[record.resourceID] = continuation
            waiting.removeValue(forKey: record.resourceID)?.resume()
        }
        return folder.appendingPathComponent(record.filename)
    }

    func waitForStart(_ id: String) async {
        if pending[id] == nil { await withCheckedContinuation { waiting[id] = $0 } }
    }

    func finish(_ id: String, fails: Bool = false) {
        let continuation = pending.removeValue(forKey: id)
        if fails { continuation?.resume(throwing: SavedBackupCheckError.differentFolder) }
        else { continuation?.resume() }
    }
}

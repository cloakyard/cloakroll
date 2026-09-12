import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Library backup presentation and ownership", .timeLimit(.minutes(1)))
@MainActor
struct LibraryBackupTests {
    @Test func historyNeverCompletesAPartialAssetAndReplacesRetryRecords() {
        var history = LibraryBackupHistory()
        let asset = BackupLibraryFixture.asset(companion: true)
        let scope = LibraryBackupHistory.Scope(sessionID: UUID(), destinationID: UUID())
        let first = BackupLibraryFixture.record(asset, resource: asset.resources[0], sessionID: scope.sessionID)
        let second = BackupLibraryFixture.record(asset, resource: asset.resources[1], sessionID: scope.sessionID, dateOffset: 1)
        let partial = BackupResult(
            snapshot: BackupSnapshot(phase: .failed, totalAssets: 1, totalResources: 2, verifiedResources: 1), records: [first]
        )
        history.apply(partial, assets: [asset], scope: scope)
        #expect(history.projection(assets: [asset], scope: scope).statuses.isEmpty)
        #expect(history.records(in: scope) == [first])

        let complete = BackupResult(
            snapshot: BackupSnapshot(phase: .completed, completedAssets: 1, verifiedResources: 2, completedAssetIDs: [asset.id]),
            records: [first, second]
        )
        history.apply(complete, assets: [asset], scope: scope)
        history.apply(complete, assets: [asset], scope: scope)
        #expect(history.records(in: scope) == [first, second])
        let projection = history.projection(assets: [asset], scope: scope)
        #expect(projection.statuses == [asset.id: .backedUp])
        #expect(projection.dates == [asset.id: second.verifiedAt])
    }

    @Test func historyIsolatesSessionDestinationDeviceAndEveryAssetMetadataChange() {
        var history = LibraryBackupHistory()
        let asset = BackupLibraryFixture.asset()
        let scope = LibraryBackupHistory.Scope(sessionID: UUID(), destinationID: UUID())
        let result = BackupResult(
            snapshot: BackupSnapshot(phase: .completed, completedAssetIDs: [asset.id]),
            records: [BackupLibraryFixture.record(asset, resource: asset.resources[0], sessionID: scope.sessionID)]
        )
        history.apply(result, assets: [asset], scope: scope)
        #expect(history.projection(assets: [asset], scope: scope).statuses[asset.id] == .backedUp)
        #expect(history.projection(assets: [asset], scope: .init(sessionID: UUID(), destinationID: scope.destinationID)).statuses.isEmpty)
        #expect(history.projection(assets: [asset], scope: .init(sessionID: scope.sessionID, destinationID: UUID())).statuses.isEmpty)

        let resource = asset.resources[0]
        let variants = [
            BackupLibraryFixture.asset(deviceID: "different-device"),
            BackupLibraryFixture.asset(createdAt: asset.createdAt?.addingTimeInterval(1)),
            BackupLibraryFixture.asset(kind: .raw),
            BackupLibraryFixture.asset(duration: 1),
            BackupLibraryFixture.asset(width: 4001),
            BackupLibraryFixture.asset(height: 3001),
            BackupLibraryFixture.asset(primary: "another-resource"),
            BackupLibraryFixture.asset(companion: true),
            BackupLibraryFixture.asset(resource: MediaResource(id: "different-resource", filename: resource.filename, byteCount: 3)),
            BackupLibraryFixture.asset(resource: MediaResource(id: resource.id, filename: "RENAMED.HEIC", byteCount: 3)),
            BackupLibraryFixture.asset(resource: MediaResource(id: resource.id, filename: resource.filename, byteCount: 4)),
            BackupLibraryFixture.asset(resource: MediaResource(
                id: resource.id, filename: resource.filename, byteCount: 3,
                modifiedAt: resource.modifiedAt?.addingTimeInterval(1)
            ))
        ]
        for changed in variants {
            #expect(history.projection(assets: [changed], scope: scope).statuses.isEmpty)
            #expect(history.projection(assets: [changed], scope: scope).dates.isEmpty)
        }
    }

    @Test func emptyCancelledRetryKeepsPriorCandidatesWithoutClaimingCompletion() {
        var history = LibraryBackupHistory()
        let asset = BackupLibraryFixture.asset(companion: true)
        let scope = LibraryBackupHistory.Scope(sessionID: UUID(), destinationID: UUID())
        let records = asset.resources.map { BackupLibraryFixture.record(asset, resource: $0, sessionID: scope.sessionID) }
        history.apply(
            BackupResult(snapshot: BackupSnapshot(phase: .completed, completedAssetIDs: [asset.id]), records: records),
            assets: [asset], scope: scope
        )
        history.apply(
            BackupResult(snapshot: BackupSnapshot(phase: .cancelled), records: []), assets: [asset], scope: scope
        )
        #expect(history.records(in: scope) == records)
        let projection = history.projection(assets: [asset], scope: scope)
        #expect(projection.statuses.isEmpty)
        #expect(projection.dates.isEmpty)
    }

    @Test func cancellingKeepsControllerBusyAndDestinationScopeUntilTheSourceSettles() async throws {
        let fixture = try BackupControllerFixture()
        let asset = BackupLibraryFixture.asset()
        let session = UUID()
        fixture.start([asset], session: session)
        await fixture.source.waitForStart("still")
        let staged = try #require(await fixture.source.lastRequest("still"))
        #expect(fixture.scope.counts.active == 1)
        #expect(FileManager.default.fileExists(atPath: staged.directory.path))
        fixture.controller.cancel()
        await fixture.source.waitForCancellation("still")
        #expect(fixture.controller.isBusy)
        #expect(fixture.controller.isStopping)
        #expect(fixture.scope.counts.stopped == 0)

        fixture.start([BackupLibraryFixture.asset(id: "ignored")], session: session)
        #expect(await fixture.source.totalCalls == 1)
        try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        await fixture.controller.waitUntilStopped()
        #expect(!fixture.controller.isBusy)
        #expect(!fixture.controller.isStopping)
        #expect(fixture.controller.snapshot?.phase == .cancelled)
        #expect(fixture.scope.counts.started == 1)
        #expect(fixture.scope.counts.stopped == 1)
        #expect(fixture.controller.projection(assets: [asset], sessionID: session).statuses.isEmpty)
        #expect(try fixture.regularFiles().isEmpty)
    }

    @Test func initialPickerCancellationNeverStartsADeviceRequestOrDestinationLease() async throws {
        let fixture = try BackupControllerFixture(hasSelection: false)
        fixture.start([BackupLibraryFixture.asset()], session: UUID())
        await fixture.controller.waitUntilStopped()
        #expect(await fixture.source.totalCalls == 0)
        #expect(fixture.scope.counts.started == 0)
        #expect(fixture.scope.counts.stopped == 0)
        #expect(!fixture.controller.isBusy)
        #expect(fixture.controller.snapshot == nil)
        #expect(fixture.controller.errorMessage == nil)
    }

    @Test func partialLivePhotoRetryReusesVerifiedComponentWithoutDuplicateCompletion() async throws {
        let fixture = try BackupControllerFixture()
        let asset = BackupLibraryFixture.asset(companion: true)
        let session = UUID()
        fixture.start([asset], session: session)
        await fixture.source.waitForStart("still")
        try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        await fixture.source.waitForStart("motion")
        try await fixture.source.fail("motion")
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(fixture.controller.snapshot?.verifiedResources == 1)
        #expect(fixture.controller.snapshot?.completedAssets == 0)
        #expect(fixture.controller.projection(assets: [asset], sessionID: session).statuses.isEmpty)
        #expect(try fixture.regularFiles().count == 1)

        fixture.start([asset], session: session)
        await fixture.source.waitForStart("motion", count: 2)
        #expect(await fixture.source.callCount("still") == 1)
        try await fixture.source.finish("motion", bytes: Data([4, 5]))
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        #expect(fixture.controller.snapshot?.completedAssets == 1)
        #expect(fixture.controller.snapshot?.verifiedResources == 2)
        #expect(fixture.controller.projection(assets: [asset], sessionID: session).statuses == [asset.id: .backedUp])

        fixture.start([asset], session: session)
        await fixture.controller.waitUntilStopped()
        #expect(await fixture.source.totalCalls == 3)
        #expect(fixture.controller.snapshot?.verifiedResources == 2)
        #expect(fixture.controller.snapshot?.completedAssets == 1)
        #expect(try fixture.regularFiles().count == 2)
        #expect(fixture.scope.counts.started == fixture.scope.counts.stopped)
    }

    @Test func terminalSnapshotSurvivesLateProgressAndDismissalDoesNotEraseHistory() async throws {
        let fixture = try BackupControllerFixture()
        let asset = BackupLibraryFixture.asset()
        let session = UUID()
        fixture.start([asset], session: session)
        await fixture.source.waitForStart("still")
        await fixture.source.report("still", downloadedBytes: 1)
        await fixture.source.report("still", downloadedBytes: 2)
        try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        await fixture.controller.waitUntilStopped()
        let terminal = try #require(fixture.controller.snapshot)
        #expect(terminal.phase == .completed)
        #expect(terminal.verifiedBytes == 3)
        #expect(terminal.completedAssetIDs == [asset.id])
        await fixture.source.report("still", downloadedBytes: 1)
        // Let the deliberately late progress callback and cancelled presentation monitor run.
        for _ in 0..<10 { await Task.yield() }
        #expect(fixture.controller.snapshot == terminal)
        fixture.controller.dismissSummary()
        #expect(fixture.controller.snapshot == nil)
        #expect(fixture.controller.projection(assets: [asset], sessionID: session).statuses[asset.id] == .backedUp)
    }
}

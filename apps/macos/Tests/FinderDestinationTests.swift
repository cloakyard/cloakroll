import Foundation
import Testing
@testable import CloakRoll

@Suite("Read-only Finder access")
@MainActor
struct FinderDestinationTests {
    @Test func finderCanOpenReadableFolderWithoutClaimingItIsWritable() async throws {
        let fixture = try BackupControllerFixture()
        let record = try #require(fixture.controller.destination.selection)
        var operations = fixture.scope.operations
        operations.validateFolder = { _ in throw BackupDestinationError.notWritable }
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: record), operations: operations,
                                                saveRecord: { _ in })
        await destination.checkFolder()
        let controller = LibraryBackupController(destination: destination)
        var opened: URL?
        await controller.revealDestination { url in
            #expect(fixture.scope.counts.active == 1)
            opened = url
        }
        #expect(opened == fixture.folder && controller.errorMessage == nil)
        #expect(fixture.scope.counts.active == 0)
        #expect(destination.readiness == .unavailable(BackupDestinationError.notWritable.message))
    }

    @Test func inaccessibleFolderDoesNotOpenFinderOrFallBackToDisplayPath() async throws {
        let fixture = try BackupControllerFixture()
        let record = try #require(fixture.controller.destination.selection)
        var operations = fixture.scope.operations
        operations.validateReadableFolder = { _ in throw BackupDestinationError.unavailable }
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: record), operations: operations,
                                                saveRecord: { _ in })
        let controller = LibraryBackupController(destination: destination)
        await controller.revealDestination { _ in Issue.record("An unavailable folder must not open Finder") }
        #expect(controller.errorMessage == BackupDestinationError.unavailable.message)
        #expect(fixture.scope.counts.active == 0)
    }
}

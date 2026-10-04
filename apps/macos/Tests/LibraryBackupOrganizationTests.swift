import BackupEngine
import Foundation
import Testing
@testable import CloakRoll

@Suite("Backup organization and persistent reuse", .timeLimit(.minutes(1)))
@MainActor
struct LibraryBackupOrganizationTests {
    @Test(arguments: BackupOrganization.allCases)
    func originalPathsSurviveReopenAndOrganizationChange(organization: BackupOrganization) async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        fixture.controller.start(
            assets: [catalog.asset], sessionID: catalog.source.sessionID, folderLayout: organization.folderLayout
        ) { request, _ in
            try writePersistentOriginal(request, byte: 7)
        }
        try #require(fixture.controller.isBusy)
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        let originalPaths = try await fixture.candidates(catalog).map(\.record.relativePath).sorted()
        #expect(originalPaths.count == 2)
        let expectedDepth = organization == .byDate ? 4 : 2
        #expect(originalPaths.allSatisfy { $0.split(separator: "/").count == expectedDepth })
        let deviceFolder = try BackupFolderLayout.deviceFolderName(for: catalog.device.id)
        #expect(originalPaths.allSatisfy { $0.hasPrefix(deviceFolder + "/") })

        let reconnected = PersistentLibraryCatalog(prefix: "reconnected", companion: true)
        let persistence = LibraryBackupPersistence(databaseURL: fixture.databaseURL)
        let controller = LibraryBackupController(destination: fixture.controller.destination, persistence: persistence)
        try await fixture.accept(reconnected, controller: controller)
        let changedOrganization: BackupOrganization = organization == .byDate ? .singleFolder : .byDate
        controller.start(
            assets: [reconnected.asset], sessionID: reconnected.source.sessionID, folderLayout: changedOrganization.folderLayout
        ) { _, _ in
            Issue.record("A layout change must not download already verified originals again")
            throw PersistentLibraryTestError.timeout
        }
        try #require(controller.isBusy)
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed)
        #expect(controller.snapshot?.transferredBytes == 0)
        #expect(controller.snapshot?.verifiedResources == 2)
        let reusedPaths = try await fixture.candidates(reconnected).map(\.record.relativePath).sorted()
        #expect(reusedPaths == originalPaths)
        for path in originalPaths {
            let url = fixture.destinationFixture.folder.appendingPathComponent(path)
            let bytes = try Data(contentsOf: url)
            #expect(bytes.allSatisfy { $0 == 7 })
        }
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }
}

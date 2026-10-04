import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

struct PersistentLibraryCatalog: Sendable {
    let device: ConnectedDevice
    let asset: MediaAsset
    let source: DeviceMediaSnapshot

    init(
        prefix: String = "old", sessionID: UUID = UUID(), contextFolder: String = "100APPLE", companion: Bool = false,
        deviceKey: String = "fixture-phone", deviceName: String = "Test iPhone"
    ) {
        device = ConnectedDevice(identity: DeviceIdentity(kind: .persistent, value: deviceKey), name: deviceName)
        let date = BackupLibraryFixture.date
        var resources = [MediaResource(id: prefix + "-still", filename: "IMG.HEIC", byteCount: 3, modifiedAt: date)]
        if companion { resources.append(MediaResource(id: prefix + "-motion", filename: "IMG.MOV", byteCount: 2, modifiedAt: date)) }
        asset = MediaAsset(
            id: prefix + "-asset", deviceID: device.id, resources: resources, kind: companion ? .livePhoto : .photo,
            createdAt: date, pixelWidth: 4000, pixelHeight: 3000
        )
        let deviceID = device.id
        let records = resources.map { resource in
            SourceMediaRecord(
                id: resource.id, deviceID: deviceID, filename: resource.filename, originalFilename: resource.filename,
                contextPath: ["DCIM", contextFolder], uti: resource.filename.hasSuffix("MOV") ? "com.apple.quicktime-movie" : "public.heic",
                byteCount: resource.byteCount, createdAt: date, modifiedAt: date, pixelWidth: 4000, pixelHeight: 3000,
                originatingAssetID: "fixture-origin", sidecarIDs: companion ? resources.filter { $0.id != resource.id }.map(\.id) : []
            )
        }
        source = DeviceMediaSnapshot(sessionID: sessionID, deviceID: device.id, revision: 1, records: records, state: .complete)
    }
}

@MainActor
final class PersistentLibraryFixture {
    let destinationFixture: BackupControllerFixture
    let databaseURL: URL
    let persistence: LibraryBackupPersistence
    let controller: LibraryBackupController

    init() throws {
        destinationFixture = try BackupControllerFixture()
        databaseURL = destinationFixture.folder.appendingPathComponent("Application Support/Backups.sqlite")
        persistence = LibraryBackupPersistence(databaseURL: databaseURL)
        controller = LibraryBackupController(destination: destinationFixture.controller.destination, persistence: persistence)
    }

    func accept(_ catalog: PersistentLibraryCatalog, controller: LibraryBackupController? = nil) async throws {
        let controller = controller ?? self.controller
        controller.acceptCatalog(source: catalog.source, assets: [catalog.asset], device: catalog.device)
        try await waitForPersistentState { !controller.isCheckingHistory }
        #expect(controller.historyErrorMessage == nil)
    }

    func backup(_ catalog: PersistentLibraryCatalog, byte: UInt8 = 1) async throws {
        controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, _ in
            try writePersistentOriginal(request, byte: byte)
        }
        try #require(controller.isBusy)
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed)
    }

    func candidates(_ catalog: PersistentLibraryCatalog) async throws -> [StoredBackupCandidate] {
        let context = try await LibraryBackupPersistence.prepare(source: catalog.source, assets: [catalog.asset], device: catalog.device)
        let destinationID = try #require(controller.destination.selection?.id)
        return try await persistence.store().candidates(
            deviceKey: catalog.device.id, destinationID: destinationID, identity: context.identity
        )
    }
}

func writePersistentOriginal(_ request: BackupDownloadRequest, byte: UInt8) throws -> DownloadedOriginal {
    let url = request.directory.appendingPathComponent(request.filename)
    try Data(repeating: byte, count: Int(request.resource.byteCount)).write(to: url, options: [.withoutOverwriting])
    return DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount)
}

@MainActor
func waitForPersistentState(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("The explicitly controlled persistent library operation did not settle")
    throw PersistentLibraryTestError.timeout
}

enum PersistentLibraryTestError: Error { case timeout }

final class PersistentTestDefaults: UserDefaults, @unchecked Sendable {
    private let stored: Data
    init(record: BackupDestination) throws {
        stored = try JSONEncoder().encode(record)
        super.init(suiteName: "CloakRollPersistentFixture-" + UUID().uuidString)!
    }
    override func data(forKey defaultName: String) -> Data? { stored }
}

final class PersistentLeaseGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var didEnter = false
    private var released = false
    var entered: Bool { condition.withLock { didEnter } }

    func waitOnce() {
        condition.lock()
        defer { condition.unlock() }
        guard !didEnter else { return }
        didEnter = true
        while !released { condition.wait() }
    }

    func release() {
        condition.withLock { released = true; condition.broadcast() }
    }
}

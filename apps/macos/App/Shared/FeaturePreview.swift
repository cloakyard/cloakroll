#if DEBUG
import AppKit
import Foundation
import MediaModels
import SwiftUI

struct FeaturePreviewWindow: View {
    @State private var model = FeaturePreview.makeModel()
    @State private var prepared = false
    @State private var settings = false

    var body: some View {
        RootView()
        .toolbar {
            ToolbarItem {
                Text("Generated files only · no OS notifications").font(.caption).foregroundStyle(.secondary)
            }
            ToolbarItem { Button("Preview Settings") { settings = true } }
        }
        .environment(model)
        .tint(Design.accent)
        .frame(minWidth: 860, minHeight: 560)
        .task {
            guard !prepared else { return }
            prepared = true
            await FeaturePreview.prepare(model)
        }
        .onDisappear { model.shutdown(); prepared = false }
        .sheet(isPresented: $settings) {
            VStack {
                SettingsView()
                Button("Done") { settings = false }.keyboardShortcut(.cancelAction).padding(.bottom)
            }.environment(model)
        }
    }
}

/// Opt-in UI acceptance environment. No device browser, personal database or real notifications.
@MainActor
enum FeaturePreview {
    static func makeModel() -> AppModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloakRoll Generated Feature Preview " + UUID().uuidString, isDirectory: true)
        let defaults = UserDefaults(suiteName: "CloakRoll.FeaturePreview." + UUID().uuidString)!
        let folder = root.appendingPathComponent("Generated Originals", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = BackupDestinationStore(defaults: defaults, selectFolder: { folder })
        let persistence = LibraryBackupPersistence(databaseURL: root.appendingPathComponent("Preview.sqlite"))
        let notifications = BackupNotifications(client: .init(permission: { .allowed }, authorize: { true },
                                                              add: { _ in }, remove: { _ in }))
        return AppModel(makeBrowser: { FeaturePreviewSource() }, preferences: LibraryPreferences(defaults: defaults),
                        backup: LibraryBackupController(destination: destination, persistence: persistence,
                                                         notifications: notifications))
    }

    static func prepare(_ model: AppModel) async {
        model.startLive()
        guard await wait({ model.assets.count == 3 && model.backupSourceAvailable }) else { return }
        await model.backup.chooseDestination()
        await model.backup.waitUntilHistoryChecked()
        await model.waitUntilProjected()
        guard !Task.isCancelled, model.backupSourceAvailable else { return }
        model.startBackup(assets: model.assets.filter { $0.resources.contains { $0.id == "sample-0" } })
        await model.backup.waitUntilStopped()
        await model.waitUntilProjected()
        guard !Task.isCancelled, model.backupSourceAvailable else { return }
        model.startBackup(assets: model.assets)
        await model.backup.waitUntilStopped()
        guard !Task.isCancelled else { return }
        model.backup.dismissSummary()
        model.navigation = .backupHealth
    }

    private static func wait(_ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !predicate(), ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        }
        return predicate()
    }
}

@MainActor
final class FeaturePreviewSource: DeviceMediaSource, OriginalMediaDownloading {
    let device = ConnectedDevice(identity: .init(kind: .persistent, value: "generated-feature-preview"),
                                 name: "Sample iPhone · Generated Files")
    let session = UUID()
    let events: AsyncStream<DeviceEvent>
    let catalogs: AsyncStream<DeviceMediaSnapshot>
    private var missingOriginalPending = true
    private let connections: AsyncStream<DeviceEvent>.Continuation
    private let library: AsyncStream<DeviceMediaSnapshot>.Continuation
    private var files: [String: Data] = [:]

    init() {
        let events = AsyncStream<DeviceEvent>.makeStream()
        self.events = events.stream
        connections = events.continuation
        let catalogs = AsyncStream<DeviceMediaSnapshot>.makeStream()
        self.catalogs = catalogs.stream
        library = catalogs.continuation
    }

    func start() {
        var records: [SourceMediaRecord] = []
        for index in 0..<3 {
            guard let image = NSImage(named: "Sample\(index)"), let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            let id = "sample-\(index)"
            files[id] = png
            let date = Date().addingTimeInterval(-Double(3 - index) * 86_400)
            records.append(SourceMediaRecord(id: id, deviceID: device.id, filename: "Generated \(index + 1).png",
                                             contextPath: ["Generated"], uti: "public.png", byteCount: Int64(png.count),
                                             createdAt: date, modifiedAt: date))
        }
        connections.yield(.stateChanged(DeviceConnection(device: device, state: .ready)))
        library.yield(DeviceMediaSnapshot(sessionID: session, deviceID: device.id, revision: 1, records: records, state: .complete))
    }

    func stop() { connections.finish(); library.finish() }
    func retry() { start() }

    func downloadOriginal(
        resourceID: String, sessionID: UUID, to directory: URL, filename: String,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal {
        guard sessionID == session else { throw MediaSourceError.staleSession }
        try Task.checkCancellation()
        if resourceID == "sample-2", missingOriginalPending {
            missingOriginalPending = false
            throw MediaSourceError.missingResource
        }
        guard let bytes = files[resourceID] else { throw MediaSourceError.missingResource }
        let file = directory.appendingPathComponent(filename)
        try bytes.write(to: file, options: .withoutOverwriting)
        progress(.init(downloadedBytes: Int64(bytes.count), totalBytes: Int64(bytes.count)))
        return DownloadedOriginal(url: file, expectedByteCount: Int64(bytes.count))
    }
}
#endif

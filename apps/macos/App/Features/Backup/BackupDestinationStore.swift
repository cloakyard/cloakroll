import AppKit
import Foundation
import Observation

struct BackupDestination: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    /// Presentation only. Access always resolves bookmarkData; this path is never a fallback.
    let lastKnownPath: String
    let bookmarkData: Data
}

/// A recent access check for presentation only. Every operation still acquires its own lease.
enum BackupDestinationReadiness: Equatable {
    case unchecked, checking, available
    case unavailable(String)

    var isChecking: Bool { self == .checking }
    var message: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }
}

enum BackupDestinationError: Error, LocalizedError, Equatable {
    case noSelection, accessDenied, unavailable, notDirectory, notWritable
    case bookmarkCreationFailed, persistenceFailed, selectionChanged

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .noSelection: "Choose a backup folder first."
        case .accessDenied: "CloakRoll couldn't access the backup folder. Choose it again to grant access."
        case .unavailable: "The backup folder isn't available. Reconnect its drive or choose another folder."
        case .notDirectory: "Choose a folder to store the backup."
        case .notWritable: "The backup folder is read-only. Choose a writable folder."
        case .bookmarkCreationFailed: "Couldn't keep access to this folder. Try choosing it again."
        case .persistenceFailed: "Couldn't save the backup folder. Try choosing it again."
        case .selectionChanged: "The backup folder changed. Start the backup again."
        }
    }
}

@MainActor @Observable
final class BackupDestinationStore {
    nonisolated static let storageKey = "backupDestination.v1"
    private(set) var selection: BackupDestination?
    private(set) var isChoosing = false
    private(set) var errorMessage: String?
    private(set) var readiness = BackupDestinationReadiness.unchecked
    @ObservationIgnored private let operations: BackupDestinationOperations
    @ObservationIgnored private let selectFolder: @MainActor () async -> URL?
    @ObservationIgnored private let saveRecord: @MainActor (Data) throws -> Void
    @ObservationIgnored private var readinessGeneration = 0
    @ObservationIgnored private var selectionGeneration = 0
    @ObservationIgnored private var acquisitionTail: Task<Void, Never>?
    @ObservationIgnored private var acquisitionID: UUID?

    init(
        defaults: UserDefaults = .standard,
        operations: BackupDestinationOperations = .live,
        selectFolder: @escaping @MainActor () async -> URL? = BackupFolderPicker.choose,
        saveRecord: (@MainActor (Data) throws -> Void)? = nil
    ) {
        self.operations = operations
        self.selectFolder = selectFolder
        self.saveRecord = saveRecord ?? { data in
            defaults.set(data, forKey: Self.storageKey)
            guard defaults.data(forKey: Self.storageKey) == data else { throw BackupDestinationError.persistenceFailed }
        }
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                let record = try JSONDecoder().decode(BackupDestination.self, from: data)
                guard !record.bookmarkData.isEmpty else { throw BackupDestinationError.unavailable }
                selection = record
            } catch { errorMessage = "The saved backup folder couldn't be read. Choose it again." }
        }
    }

    func clearError() { errorMessage = nil }

    @discardableResult
    func chooseFolder() async -> Bool {
        guard !isChoosing else { return false }
        isChoosing = true
        errorMessage = nil
        defer { isChoosing = false }
        guard let url = await selectFolder(), !Task.isCancelled else { return false }
        let previous = selection
        let operations = operations
        do {
            let record = try await Self.work { try operations.prepareSelection(url: url, previous: previous) }
            try Task.checkCancellation()
            guard selection?.id == previous?.id else { throw BackupDestinationError.selectionChanged }
            try persist(record)
            selection = record
            selectionGeneration += 1
            readinessGeneration += 1
            readiness = .unchecked
            await checkFolder(allowWhileChoosing: true)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func acquireLease() async throws -> DestinationLease {
        guard let destinationID = selection?.id else { throw BackupDestinationError.noSelection }
        readinessGeneration += 1
        let generation = readinessGeneration
        let selectionGeneration = selectionGeneration
        let preceding = acquisitionTail
        let identifier = UUID()
        let acquisition = Task {
            // Each operation needs an independently owned lease, but bookmark refresh must
            // finish before another operation captures the selected record.
            if let preceding { await preceding.value }
            try Task.checkCancellation()
            guard self.selectionGeneration == selectionGeneration, let original = selection else {
                throw BackupDestinationError.selectionChanged
            }
            return try await acquire(original, selectionGeneration: selectionGeneration)
        }
        acquisitionID = identifier
        let tail = Task { _ = await acquisition.result }
        acquisitionTail = tail
        defer {
            if acquisitionID == identifier {
                acquisitionTail = nil
                acquisitionID = nil
            }
        }
        do {
            let lease = try await withTaskCancellationHandler {
                try await acquisition.value
            } onCancel: { acquisition.cancel() }
            // The queue must drop its task-result ownership before the caller owns the lease.
            // Await this operation's tail, never a later caller's mutable acquisitionTail.
            await tail.value
            if Task.isCancelled {
                lease.release()
                throw CancellationError()
            }
            if isCurrentCheck(generation, destinationID: destinationID) {
                readiness = .available
                errorMessage = nil
            }
            return lease
        } catch {
            if isCurrentCheck(generation, destinationID: destinationID) {
                readiness = error is CancellationError ? .unchecked : .unavailable(Self.message(for: error))
                if !(error is CancellationError) { errorMessage = Self.message(for: error) }
            }
            throw error
        }
    }

    /// An explicit check has inline status, and never opens a picker, mounts a drive or writes
    /// a test file. A cached Available result is never used to authorize a later operation.
    func checkFolder() async {
        await checkFolder(allowWhileChoosing: false)
    }

    private func checkFolder(allowWhileChoosing: Bool) async {
        guard let original = selection, !isChoosing || allowWhileChoosing else { return }
        readinessGeneration += 1
        let generation = readinessGeneration
        readiness = .checking
        let operations = operations
        do {
            // Advisory checks never persist refreshed bookmarks. A concurrent real lease
            // owns that update, and must not be invalidated by a presentation-only check.
            try await Self.work {
                let acquired = try operations.acquire(original)
                acquired.lease.release()
            }
            try Task.checkCancellation()
            guard isCurrentCheck(generation, destinationID: original.id) else { return }
            guard selection == original else { readiness = .unchecked; return }
            readiness = .available
            errorMessage = nil
        } catch {
            guard isCurrentCheck(generation, destinationID: original.id) else { return }
            guard selection == original else { readiness = .unchecked; return }
            readiness = error is CancellationError ? .unchecked : .unavailable(Self.message(for: error))
        }
    }

    private func isCurrentCheck(_ generation: Int, destinationID: UUID) -> Bool {
        readinessGeneration == generation && selection?.id == destinationID
    }

    private func acquire(_ original: BackupDestination, selectionGeneration: Int) async throws -> DestinationLease {
        let operations = operations
        let acquired = try await Self.work { try operations.acquire(original) }
        var handedOff = false
        defer { if !handedOff { acquired.lease.release() } }
        try Task.checkCancellation()
        guard self.selectionGeneration == selectionGeneration, selection == original else {
            throw BackupDestinationError.selectionChanged
        }
        if acquired.record != original {
            try persist(acquired.record)
            selection = acquired.record
        }
        handedOff = true
        return acquired.lease
    }

    private func persist(_ record: BackupDestination) throws {
        do { try saveRecord(JSONEncoder().encode(record)) } catch { throw BackupDestinationError.persistenceFailed }
    }

    private static func message(for error: any Error) -> String {
        (error as? BackupDestinationError)?.message ?? BackupDestinationError.unavailable.message
    }

    private nonisolated static func work<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

@MainActor
private enum BackupFolderPicker {
    static func choose() async -> URL? {
        guard !Task.isCancelled else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        let lifecycle = BackupFolderPickerLifecycle(panel: panel)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                let completion: (NSApplication.ModalResponse) -> Void = { response in
                    guard !lifecycle.didFinish else { return }
                    lifecycle.didFinish = true
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
                lifecycle.didBegin = true
                if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
                    panel.beginSheetModal(for: window, completionHandler: completion)
                } else {
                    panel.begin(completionHandler: completion)
                }
            }
        } onCancel: {
            Task { @MainActor in lifecycle.cancel() }
        }
    }
}

@MainActor
private final class BackupFolderPickerLifecycle {
    let panel: NSOpenPanel
    var didBegin = false
    var didFinish = false

    init(panel: NSOpenPanel) { self.panel = panel }

    func cancel() {
        guard didBegin, !didFinish else { return }
        panel.cancel(nil)
    }
}

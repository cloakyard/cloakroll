import AppKit
import BackupEngine
import Observation

/// Owns an opening operation until its physical read settles; obsolete results never present UI.
@MainActor @Observable
final class SavedOriginalActions {
    typealias Resolve = @Sendable (URL, VerifiedBackupResource) async throws -> URL
    var preview: SavedPreviewRequest?
    var errorMessage: String?
    private(set) var isOpening = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let resolve: Resolve
    @ObservationIgnored private let reveal: @MainActor (URL) -> Void

    init(resolve: @escaping Resolve = { try await SavedOriginalAccess.url(destination: $0, record: $1) },
         reveal: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }) {
        self.resolve = resolve
        self.reveal = reveal
    }

    @discardableResult
    func open(_ record: VerifiedBackupResource, folder: BackupDestinationStore, previewing: Bool) -> Task<Void, Never> {
        cancel()
        let requested = generation
        isOpening = true
        let operation = Task {
            defer {
                if requested == generation { isOpening = false; task = nil }
            }
            do {
                let lease = try await folder.acquireLease(readOnly: true)
                let url = try await resolve(lease.url, record)
                try Task.checkCancellation()
                guard requested == generation else { return }
                if previewing {
                    preview = SavedPreviewRequest(url: url, lease: lease)
                } else {
                    reveal(url)
                    lease.release()
                }
            } catch is CancellationError {
                return
            } catch {
                guard requested == generation else { return }
                errorMessage = "This original is missing, changed or inaccessible. "
                    + "Check the folder and run Check Saved Files for integrity."
            }
        }
        task = operation
        return operation
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isOpening = false
        preview = nil
        errorMessage = nil
    }
}

import AppKit
import MediaModels

extension AppModel {
    func showSelectedInfo() {
        if let activeID, selection.selectedIDs.contains(activeID) {
            infoAsset = currentAsset(id: activeID)
            return
        }
        guard let id = snapshot.orderedIDs.first(where: selection.selectedIDs.contains) else { return }
        infoAsset = currentAsset(id: id)
    }

    var canBackUp: Bool {
        isViewingLibrary && backupSourceAvailable && (!selection.selectedIDs.isEmpty || snapshot.visibleNewCount > 0)
    }

    func backUpCurrentSelection() {
        guard canBackUp else { return }
        startBackup(assets: backupCandidates(context: nil))
    }

    func canBackUp(asset: MediaAsset) -> Bool {
        isViewingLibrary && backupSourceAvailable && currentAsset(id: asset.id) == asset
    }

    func backUpFromContext(asset: MediaAsset) {
        guard canBackUp(asset: asset) else { return }
        startBackup(assets: backupCandidates(context: asset))
    }

    /// Context actions use the selected batch only if the clicked item belongs to it.
    /// A click outside that batch acts on that item without mutating the existing selection.
    func backupCandidates(context: MediaAsset?) -> [MediaAsset] {
        let selected = selection.selectedIDs
        if let context, !selected.contains(context.id) {
            return currentAsset(id: context.id) == context ? [context] : []
        }
        return snapshot.sections.flatMap(\.assets).filter {
            selected.isEmpty ? status(for: $0) != .backedUp : selected.contains($0.id)
        }
    }

    var canRetryBackup: Bool {
        guard isViewingLibrary, backupSourceAvailable, let attempt = backup.lastAttempt else { return false }
        return attempt.matches(sessionID: catalogSessionID, currentAsset: currentAsset(id:))
    }

    func retryLastBackup() {
        guard canRetryBackup, let attempt = backup.lastAttempt else { return }
        startBackup(assets: attempt.assets)
    }

    var canCheckSavedOriginals: Bool {
        isViewingLibrary && !isSample && deviceState == .ready && mediaScanState == .complete
            && catalogSessionID != nil && !isCatalogPreparing && !isProjecting
            && !backup.isBusy && !backup.isCheckingHistory && !backup.destination.isChoosing
            && backup.destination.selection != nil && backup.persistence != nil
    }

    func checkSavedOriginals() {
        guard canCheckSavedOriginals else { return }
        backup.retryHistoryCheck()
    }

    var selectedFilenames: [String] {
        snapshot.orderedIDs.compactMap { selection.selectedIDs.contains($0) ? currentAsset(id: $0)?.filename : nil }
    }

    func copySelectedFilenames() {
        let filenames = selectedFilenames
        guard isViewingLibrary, !filenames.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filenames.joined(separator: "\n"), forType: .string)
    }
}

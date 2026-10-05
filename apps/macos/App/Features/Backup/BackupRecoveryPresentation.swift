import MediaModels

enum BackupRetryState {
    case ready, connectDevice, readingLibrary, checkingHistory, historyUnavailable, choosingFolder, chooseItems, showLibrary

    var message: String? {
        switch self {
        case .ready: nil
        case .connectDevice: "Reconnect and unlock your iPhone to continue."
        case .readingLibrary: "Wait for the iPhone library to finish loading."
        case .checkingHistory: "Checking saved originals before you continue…"
        case .historyUnavailable: "Retry the backup history check before continuing."
        case .choosingFolder: "Finish choosing the backup folder to continue."
        case .chooseItems: "Choose items from the current library. Saved originals are checked before they are reused."
        case .showLibrary: "Open the library to continue this backup."
        }
    }
}

extension AppModel {
    var backupRetryState: BackupRetryState {
        guard isViewingLibrary else { return .showLibrary }
        if canRetryBackup { return .ready }
        guard deviceState == .ready else { return .connectDevice }
        if isCatalogLoading || isProjecting || mediaScanState != .complete { return .readingLibrary }
        if backup.isCheckingHistory { return .checkingHistory }
        if backup.historyErrorMessage != nil { return .historyUnavailable }
        if backup.destination.isChoosing { return .choosingFolder }
        return .chooseItems
    }

    var showsBackupBar: Bool {
        !backup.recovery.isRunning && (backup.isBusy || sampleProgress || backup.snapshot != nil || (isViewingLibrary && !assets.isEmpty))
    }
}

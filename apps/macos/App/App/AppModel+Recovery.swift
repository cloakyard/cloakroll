import BackupEngine
import Foundation

extension AppModel {
    func rebuildBackupHistory(mode: BackupFolderRecoveryController.Mode) async {
        guard !backup.isBusy, !backup.isCheckingHistory,
              let destinationID = backup.destination.selection?.id, let persistence = backup.persistence else { return }
        let context = backup.recoveryContext
        let download = originalDownload
        guard mode != .usb || (context != nil && download != nil) else { return }
        backup.suspendHistory()
        await backup.recovery.run(mode: mode, selectedDestinationID: destinationID, destination: backup.destination,
                                  persistence: persistence, context: context, download: download)
        backup.retryHistoryCheck()
    }

}

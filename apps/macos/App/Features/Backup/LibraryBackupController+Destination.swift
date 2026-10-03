import Foundation

extension LibraryBackupController {
    /// A successful folder retry also retries a previously blocked history check. Merely
    /// opening Settings does not start another scan when history has no error.
    func checkDestination() async {
        guard !isBusy, !destination.isChoosing else { return }
        let destinationID = destination.selection?.id
        await destination.checkFolder()
        guard !Task.isCancelled, !isBusy, destinationID != nil,
              destination.selection?.id == destinationID, destination.readiness == .available,
              historyErrorMessage != nil else { return }
        retryHistoryCheck()
    }
}

import Foundation
import MediaModels

extension LibraryBackupController {
    func useDevice(_ device: ConnectedDevice?) {
        guard destination.selectDevice(device) else { return }
        if !isBusy { dismissSummary() }
        onStatusesChanged?()
        Task { await destination.checkFolder() }
    }

    func restorePreviousDestination(for device: ConnectedDevice) async throws {
        guard destination.selection == nil, device.identity?.isPersistent == true, let persistence else { return }
        let session = try await persistence.store().lastCompletedSession(deviceKey: device.id)
        try Task.checkCancellation()
        try destination.restoreHistoricalDestination(session?.destinationID, device: device)
    }

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

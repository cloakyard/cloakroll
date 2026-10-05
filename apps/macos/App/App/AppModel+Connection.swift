import MediaModels

extension AppModel {
    func applyConnection(_ connection: DeviceConnection) {
        guard device != connection.device || deviceState != connection.state || deviceMessage != connection.message else { return }
        if device?.id != connection.device?.id {
            backup.sourceBecameUnavailable()
            backup.suspendHistory(resetSource: true)
        }
        device = connection.device
        deviceState = connection.state
        deviceMessage = connection.message
        if connection.state != .ready {
            backup.sourceBecameUnavailable()
            backup.suspendHistory()
        }
        backup.useDevice(connection.device)
        if connection.state == .ready {
            backup.retryHistoryCheck()
        }
        if connection.state != .ready { thumbnails.setSession(nil) } else if mediaScanState != .interrupted {
            thumbnails.setSession(catalogSessionID)
        }
    }
}

import MediaModels

enum MediaInfoDirection { case previous, next }

struct MediaInfoPosition: Equatable {
    let index: Int
    let count: Int
    let previousID: String?
    let nextID: String?
}

extension AppModel {
    func infoPosition(for asset: MediaAsset) -> MediaInfoPosition? {
        guard isViewingLibrary, deviceState == .ready, !isProjecting, !isCatalogPreparing,
              infoAsset == asset, currentAsset(id: asset.id) == asset,
              isSample || device?.id == asset.deviceID,
              let index = snapshot.orderedIDs.firstIndex(of: asset.id) else { return nil }
        let ids = snapshot.orderedIDs
        return MediaInfoPosition(
            index: index, count: ids.count,
            previousID: index > 0 ? ids[index - 1] : nil,
            nextID: index + 1 < ids.count ? ids[index + 1] : nil
        )
    }

    /// Info browsing never changes the grid's selection, active item or range anchor.
    /// Re-evaluate the current projection at activation, so a stale button cannot navigate.
    func moveInfo(_ direction: MediaInfoDirection, from asset: MediaAsset) {
        guard let position = infoPosition(for: asset) else { return }
        let id = direction == .previous ? position.previousID : position.nextID
        guard let id, let target = currentAsset(id: id), target.deviceID == asset.deviceID else { return }
        infoAsset = target
    }
}

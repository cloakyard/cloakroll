import Foundation
import MediaModels

/// A menu action belongs to one projection and connection, never just a reusable date ID.
struct DateGroupSelectionTarget: Equatable {
    let sectionID: String
    let revision: Int
    let sessionID: UUID?
}

struct DateGroupSelectionState {
    let total: Int
    let selected: Int
    var canSelect: Bool { selected < total }
    var canDeselect: Bool { selected > 0 }
}

extension AppModel {
    func dateGroupTarget(sectionID: String) -> DateGroupSelectionTarget {
        DateGroupSelectionTarget(sectionID: sectionID, revision: snapshotRevision, sessionID: catalogSessionID)
    }

    var activeDateGroupTarget: DateGroupSelectionTarget? {
        guard let activeID,
              let section = snapshot.sections.first(where: { $0.assets.contains { $0.id == activeID } }) else { return nil }
        return dateGroupTarget(sectionID: section.id)
    }

    func dateGroupState(for target: DateGroupSelectionTarget) -> DateGroupSelectionState? {
        guard let section = currentDateGroup(for: target) else { return nil }
        return DateGroupSelectionState(
            total: section.assets.count,
            selected: section.assets.reduce(0) { $0 + (selection.selectedIDs.contains($1.id) ? 1 : 0) }
        )
    }

    func currentDateGroup(for target: DateGroupSelectionTarget) -> MediaSection? {
        guard isViewingLibrary, presentation == nil, deviceState == .ready, !isProjecting, !isCatalogPreparing,
              target.revision == snapshotRevision, target.sessionID == catalogSessionID,
              let section = snapshot.sections.first(where: { $0.id == target.sectionID }), !section.assets.isEmpty,
              isSample || section.assets.allSatisfy({ $0.deviceID == device?.id }) else { return nil }
        return section
    }
}

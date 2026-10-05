import Foundation

/// One preferences value publishes the current selection and remembered identities together.
/// Bookmarks authorize resolution; display names and paths are never matching evidence.
struct BackupDestinationArchive: Codable {
    let version: Int
    let selectedID: UUID
    let destinations: [BackupDestination]
    let deviceFolders: [String: UUID]

    var selection: BackupDestination? { destinations.first { $0.id == selectedID } }

    init(selecting record: BackupDestination, remembered: [BackupDestination], deviceFolders: [String: UUID] = [:]) {
        version = 2
        selectedID = record.id
        destinations = [record] + remembered.filter { $0.id != record.id }
        self.deviceFolders = deviceFolders
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let archive: Self
        if let legacy = try? decoder.decode(BackupDestination.self, from: data) {
            archive = Self(selecting: legacy, remembered: [])
        } else {
            archive = try decoder.decode(Self.self, from: data)
        }
        guard archive.version == 2, archive.selection != nil,
              Set(archive.destinations.map(\.id)).count == archive.destinations.count,
              archive.destinations.allSatisfy({ !$0.bookmarkData.isEmpty }),
              archive.deviceFolders.allSatisfy({ key, id in
                  !key.isEmpty && archive.destinations.contains { $0.id == id }
              }) else {
            throw BackupDestinationError.unavailable
        }
        return archive
    }
}

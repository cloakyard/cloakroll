import BackupEngine

/// User-facing choices always preserve a separate destination folder for each iPhone.
enum BackupOrganization: String, CaseIterable {
    case byDate
    case singleFolder

    var title: String {
        switch self {
        case .byDate: "Year and Month"
        case .singleFolder: "One Folder"
        }
    }

    var folderLayout: BackupFolderLayout {
        switch self {
        case .byDate: .byDevice
        case .singleFolder: .byDeviceFlat
        }
    }
}

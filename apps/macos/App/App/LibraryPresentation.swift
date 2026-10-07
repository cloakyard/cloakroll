import MediaModels

enum LibraryPresentation: Identifiable {
    case mediaInfo(MediaAsset)
    case help(BackupHelpTopic)

    var id: String {
        switch self {
        // Browsing updates one sheet instead of dismissing/reopening it for each item.
        case .mediaInfo: "media-info"
        case .help(let topic): "help:\(topic.rawValue)"
        }
    }
}

extension AppModel {
    var infoAsset: MediaAsset? {
        get {
            guard case .mediaInfo(let asset) = presentation else { return nil }
            return asset
        }
        set {
            if let newValue {
                presentation = .mediaInfo(newValue)
            } else if case .mediaInfo = presentation {
                presentation = nil
            }
        }
    }
}

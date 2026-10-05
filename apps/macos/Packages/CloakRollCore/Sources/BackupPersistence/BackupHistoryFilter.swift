import Foundation

public struct BackupHistoryFilter: Sendable, Equatable, Hashable {
    public enum Outcome: Sendable, Hashable { case all, completed, unfinished }

    public var deviceKey: String?
    public var outcome: Outcome

    public init(deviceKey: String? = nil, outcome: Outcome = .all) {
        self.deviceKey = deviceKey
        self.outcome = outcome
    }
}

/// Identity comes from the saved device key, never its editable display name.
public struct BackupHistoryDevice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

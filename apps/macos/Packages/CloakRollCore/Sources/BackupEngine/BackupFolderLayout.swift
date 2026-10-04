import CryptoKit
import Foundation
import MediaModels

/// Organization applies only to newly published originals. Previously verified paths remain
/// valid in either layout and are never renamed or moved as part of an incremental backup.
public enum BackupFolderLayout: Equatable, Sendable {
    case byDate
    case byDevice

    /// A versioned, deterministic folder component. Display names are deliberately excluded:
    /// renaming an iPhone must not split its future originals across different folders.
    /// A 128-bit digest token keeps the raw device key out of the filesystem name.
    public static func deviceFolderName(for deviceID: String) throws -> String {
        guard !deviceID.isEmpty else { throw BackupEngineError.invalidSelection }
        let key = "CloakRoll device folder v1\0" + deviceID.precomposedStringWithCanonicalMapping
        return "iPhone " + HexEncoding.lowercase(SHA256.hash(data: Data(key.utf8)).prefix(16))
    }

    func folderPrefix(deviceID: String) throws -> [String] {
        switch self {
        case .byDate: []
        case .byDevice: [try Self.deviceFolderName(for: deviceID)]
        }
    }
}

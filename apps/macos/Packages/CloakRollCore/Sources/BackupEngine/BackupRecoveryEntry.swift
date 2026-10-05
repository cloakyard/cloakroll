import CryptoKit
import Foundation
import MediaModels

/// Portable evidence, stored beside the originals. A receipt is an intent, not proof that its
/// file still exists: every import must check the current file's complete size and SHA-256.
public struct BackupRecoveryEntry: Codable, Equatable, Sendable {
    public struct Component: Codable, Equatable, Sendable {
        public let canonical: String
        public let digest: String
        public let reusable: Bool
        public let filename: String
        public let byteCount: Int64
        public let sourceSignature: String

        public init(canonical: String, digest: String, reusable: Bool, filename: String, byteCount: Int64, sourceSignature: String) {
            self.canonical = canonical
            self.digest = digest
            self.reusable = reusable
            self.filename = filename
            self.byteCount = byteCount
            self.sourceSignature = sourceSignature
        }
    }

    public let version: Int
    public let deviceKey: String
    public let deviceName: String
    public let persistentDevice: Bool
    public let assetCanonical: String
    public let assetDigest: String
    public let assetReusable: Bool
    public let components: [Component]
    public let resourceDigest: String
    public let record: VerifiedBackupResource

    public init(deviceKey: String, deviceName: String, persistentDevice: Bool, assetCanonical: String,
                assetDigest: String, assetReusable: Bool, components: [Component], resourceDigest: String,
                record: VerifiedBackupResource) {
        version = 1
        self.deviceKey = deviceKey
        self.deviceName = deviceName
        self.persistentDevice = persistentDevice
        self.assetCanonical = assetCanonical
        self.assetDigest = assetDigest
        self.assetReusable = assetReusable
        self.components = components.sorted { $0.digest < $1.digest }
        self.resourceDigest = resourceDigest
        self.record = record
    }

    /// Stable across connection handles and repeated backups of the same saved bytes.
    public var key: String {
        let fields = [deviceKey, assetDigest, resourceDigest, record.relativePath, String(record.byteCount), record.sha256]
        return Self.digest((try? JSONEncoder().encode(fields)) ?? Data())
    }

    public func validate() throws {
        guard version == 1, !deviceKey.isEmpty, !deviceName.isEmpty, record.deviceID == deviceKey,
              Self.digest(Data(assetCanonical.utf8)) == assetDigest, !assetCanonical.isEmpty,
              !assetReusable || persistentDevice, !components.isEmpty, components.count <= 100,
              Set(components.map(\.digest)).count == components.count,
              let component = components.first(where: { $0.digest == resourceDigest }),
              component.filename == record.filename, component.byteCount == record.byteCount,
              component.sourceSignature == record.sourceMetadataSignature,
              Self.isDigest(record.sha256), record.verifiedAt.timeIntervalSince1970.isFinite,
              record.sourceModifiedAt?.timeIntervalSince1970.isFinite != false,
              Self.isMediaPath(record.relativePath) else { throw BackupRecoveryError.invalidIndex }
        try validateMembership()
        var total: Int64 = 0
        for part in components {
            guard !part.canonical.isEmpty, Self.digest(Data(part.canonical.utf8)) == part.digest,
                  !part.reusable || assetReusable, part.byteCount > 0,
                  BackupDescriptor.isComponent(part.filename), Self.isDigest(part.sourceSignature) else {
                throw BackupRecoveryError.invalidIndex
            }
            let next = total.addingReportingOverflow(part.byteCount)
            guard !next.overflow else { throw BackupRecoveryError.invalidIndex }
            total = next.partialValue
        }
    }

    private func validateMembership() throws {
        guard var asset = try JSONSerialization.jsonObject(with: Data(assetCanonical.utf8)) as? [String: Any] else {
            throw BackupRecoveryError.invalidIndex
        }
        if let nested = asset["evidence"] as? String {
            guard let evidence = try JSONSerialization.jsonObject(with: Data(nested.utf8)) as? [String: Any] else {
                throw BackupRecoveryError.invalidIndex
            }
            asset = evidence
        }
        guard let members = asset["components"] as? [Any], members.count == components.count else {
            throw BackupRecoveryError.invalidIndex
        }
        // Production identity v1 embeds the exact resource membership in its canonical JSON.
        // Keep the generic count check for earlier opaque canonical representations as well.
        if let members = members as? [String] {
            let resourceMembers = try components.map { part -> String in
                guard let resource = try JSONSerialization.jsonObject(with: Data(part.canonical.utf8)) as? [String: Any],
                      resource["assetDigest"] as? String == assetDigest, let member = resource["component"] as? String else {
                    throw BackupRecoveryError.invalidIndex
                }
                return member
            }
            guard resourceMembers.sorted() == members.sorted() else { throw BackupRecoveryError.invalidIndex }
        }
    }

    public static func isMediaPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !parts.isEmpty && parts.allSatisfy { BackupDescriptor.isComponent($0) && !$0.hasPrefix(".") }
    }

    static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func digest(_ data: Data) -> String { HexEncoding.lowercase(SHA256.hash(data: data)) }
}

public enum BackupRecoveryError: Error, LocalizedError, Sendable {
    case invalidIndex, tooLarge, libraryChanged

    public var errorDescription: String? {
        switch self {
        case .invalidIndex: "The folder’s recovery information is invalid or uses an unsupported version. No originals were changed."
        case .tooLarge: "This folder exceeds the recovery scan limit. Choose a smaller backup folder."
        case .libraryChanged: "The iPhone library changed. Reconnect and wait for it to finish loading, then try again."
        }
    }
}

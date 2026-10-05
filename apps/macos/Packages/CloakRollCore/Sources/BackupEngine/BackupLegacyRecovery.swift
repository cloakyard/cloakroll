import Darwin
import Foundation
import MediaModels

/// One-time proof for media-only folders. Sizes only narrow candidates; only a full USB
/// original matching a freshly hashed saved file can produce a receipt. Originals stay in place.
public enum BackupLegacyRecovery {
    public static func run(
        assets: [MediaAsset], device: ConnectedDevice, identity: BackupCatalogIdentity, destination: URL,
        existing: BackupRecoveryScan, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        download: @escaping BackupEngine.Download
    ) async throws -> BackupRecoveryScan {
        guard identity.deviceKey == device.id, assets.allSatisfy({ $0.deviceID == device.id }) else {
            throw BackupRecoveryError.libraryChanged
        }
        let root = try BackupRecoveryIndex.openRoot(destination)
        let status = try root.status()
        guard existing.destinationIdentity == "\(status.st_dev):\(status.st_ino)" else { throw BackupRecoveryError.libraryChanged }
        let sizes = Set(assets.flatMap(\.resources).map(\.byteCount).filter { $0 > 0 })
        var candidates: [Int64: [String]] = [:]
        var visited = 0
        try enumerate(root, prefix: [], sizes: sizes, visited: &visited, candidates: &candidates)
        var entries = existing.entries
        let known = Set(existing.entries.filter { $0.deviceKey == device.id }.map { [$0.assetDigest, $0.resourceDigest] })
        let work = assets.flatMap { asset in asset.resources.map { (asset, $0) } }.filter { asset, resource in
            guard let assetIdentity = identity.assets[asset.id], let part = assetIdentity.resources[resource.id] else { return false }
            return candidates[resource.byteCount] != nil && !known.contains([assetIdentity.digest, part.digest])
        }
        guard !work.isEmpty else { return existing }
        let staging = try BackupFileStore(destination: destination, runID: UUID(), timeZone: .current, usesDateFolders: false)
        defer { staging.closeStaging() }
        var hashes: [Int64: [String: String]] = [:]
        for (offset, pair) in work.enumerated() {
            try Task.checkCancellation()
            let (asset, resource) = pair
            if hashes[resource.byteCount] == nil {
                hashes[resource.byteCount] = try hashCandidates(root, paths: candidates[resource.byteCount] ?? [],
                    bytes: resource.byteCount)
            }
            guard let local = hashes[resource.byteCount], !local.isEmpty else { progress(offset + 1, work.count); continue }
            try staging.checkCapacity(for: resource.byteCount, using: .live)
            let temporary = try staging.prepare(filename: resource.filename)
            defer { staging.discard(temporary) }
            let received = try await download(BackupDownloadRequest(resource: resource, sessionID: identity.sessionID,
                                                                    directory: temporary.directory, filename: temporary.filename), { _ in })
            try Task.checkCancellation()
            guard received.expectedByteCount == resource.byteCount else { throw BackupEngineError.sourceSizeChanged }
            let verified = try staging.verifyStaged(temporary, returnedURL: received.url,
                expectedByteCount: resource.byteCount, createdAt: nil)
            if let path = local[verified.evidence.sha256],
               try BackupReadOnlyFiles.verifyExisting(root: root, relativePath: path, expectedByteCount: resource.byteCount,
                                                      sha256: verified.evidence.sha256) {
                let record = try VerifiedBackupResource(
                    assetID: asset.id, resourceID: resource.id, deviceID: device.id, sourceSessionID: identity.sessionID,
                    filename: resource.filename, relativePath: path, byteCount: resource.byteCount, sha256: verified.evidence.sha256,
                    verifiedAt: Date(), sourceModifiedAt: resource.modifiedAt, destinationIdentity: staging.destinationIdentity,
                    sourceMetadataSignature: BackupEngine.sourceSignature(asset: asset, resource: resource)
                )
                let entry = try makeEntry(asset: asset, device: device, identity: identity, record: record)
                try BackupRecoveryIndex.write(entry, destination: destination)
                entries.append(entry)
            }
            try staging.discardVerified(verified)
            progress(offset + 1, work.count)
        }
        return BackupRecoveryIndex.resolved(entries, checked: existing.checked + work.count, unavailable: existing.unavailable,
                                            invalid: existing.invalid, identity: existing.destinationIdentity)
    }

    private static func makeEntry(asset: MediaAsset, device: ConnectedDevice, identity: BackupCatalogIdentity,
                                  record: VerifiedBackupResource) throws -> BackupRecoveryEntry {
        guard let key = identity.assets[asset.id], let resourceKey = key.resources[record.resourceID] else {
            throw BackupRecoveryError.libraryChanged
        }
        let components = try asset.resources.map { resource in
            guard let part = key.resources[resource.id] else { throw BackupRecoveryError.libraryChanged }
            return try BackupRecoveryEntry.Component(canonical: part.canonical, digest: part.digest,
                                                      reusable: part.isReusableAcrossConnections, filename: resource.filename,
                                                      byteCount: resource.byteCount,
                                                      sourceSignature: BackupEngine.sourceSignature(asset: asset, resource: resource))
        }
        return BackupRecoveryEntry(deviceKey: device.id, deviceName: device.name, persistentDevice: device.identity?.isPersistent == true,
                                   assetCanonical: key.canonical, assetDigest: key.digest, assetReusable: key.isReusableAcrossConnections,
                                   components: components, resourceDigest: resourceKey.digest, record: record)
    }

    private static func enumerate(_ directory: BackupDescriptor, prefix: [String], sizes: Set<Int64>, visited: inout Int,
                                  candidates: inout [Int64: [String]]) throws {
        guard prefix.count <= 32 else { throw BackupRecoveryError.tooLarge }
        for name in try directory.entries(limit: 200_000).sorted() where !name.hasPrefix(".") {
            try Task.checkCancellation()
            visited += 1
            guard visited <= 200_000 else { throw BackupRecoveryError.tooLarge }
            var status = stat()
            guard fstatat(directory.value, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else { throw BackupFileError.unavailable(errno) }
            if (status.st_mode & S_IFMT) == S_IFDIR {
                try enumerate(directory.directory(name), prefix: prefix + [name], sizes: sizes, visited: &visited, candidates: &candidates)
            } else if (status.st_mode & S_IFMT) == S_IFREG, status.st_nlink == 1, sizes.contains(status.st_size) {
                candidates[status.st_size, default: []].append((prefix + [name]).joined(separator: "/"))
            }
        }
    }

    private static func hashCandidates(_ root: BackupDescriptor, paths: [String], bytes: Int64) throws -> [String: String] {
        var hashes: [String: String] = [:]
        for path in paths.sorted() {
            try Task.checkCancellation()
            do {
                let evidence = try BackupFileEvidence.inspect(BackupReadOnlyFiles.namedFile(root: root, relativePath: path),
                    expectedBytes: bytes)
                if BackupReadOnlyFiles.matches(root: root, relativePath: path, evidence: evidence), hashes[evidence.sha256] == nil {
                    hashes[evidence.sha256] = path
                }
            } catch is CancellationError { throw CancellationError() } catch { continue }
        }
        return hashes
    }
}

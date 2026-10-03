import Darwin
import Foundation

public enum BackupRecovery {
    /// Reads only the exact journaled names. The caller retains destination access until this
    /// finishes. This never searches by filename, modifies bytes, or publishes staged content.
    public static func inspect(destination: URL, intent: BackupPublicationIntent) async throws -> BackupRecoveryOutcome {
        let task = Task.detached(priority: .utility) { try inspectLocal(destination: destination, intent: intent) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static func inspectLocal(destination: URL, intent: BackupPublicationIntent) throws -> BackupRecoveryOutcome {
        try Task.checkCancellation()
        guard destination.isFileURL else { throw BackupFileError.unsafePath }
        let root = try BackupDescriptor(open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        let status = try root.status()
        guard intent.staging.destinationIdentity == "\(status.st_dev):\(status.st_ino)",
              intent.byteCount > 0, intent.byteCount == intent.staging.expectedByteCount,
              intent.sha256.count == 64, intent.sha256.allSatisfy({ $0.isHexDigit }),
              !intent.staging.sourceMetadataSignature.isEmpty,
              intent.relativePath != intent.staging.stagingRelativePath else { return .unavailable }
        if try matches(root: root, path: intent.relativePath, intent: intent, includingChangeTime: false) {
            return .published(intent.verifiedRecord)
        }
        guard try hasOwnedStaging(root: root, intent: intent.staging) else { return .unavailable }
        if try matches(root: root, path: intent.staging.stagingRelativePath, intent: intent, includingChangeTime: true) {
            return .staged
        }
        return .unavailable
    }

    private static func matches(
        root: BackupDescriptor, path: String, intent: BackupPublicationIntent, includingChangeTime: Bool
    ) throws -> Bool {
        do {
            let file = try BackupReadOnlyFiles.namedFile(root: root, relativePath: path)
            let evidence = try BackupFileEvidence.inspect(file, expectedBytes: intent.byteCount)
            let saved = intent.fileIdentity
            let actual = evidence.identity
            guard actual.device == saved.device, actual.inode == saved.inode,
                  actual.birthSeconds == saved.birthSeconds, actual.birthNanoseconds == saved.birthNanoseconds,
                  actual.modifiedSeconds == saved.modifiedSeconds, actual.modifiedNanoseconds == saved.modifiedNanoseconds,
                  !includingChangeTime || (actual.changedSeconds == saved.changedSeconds
                    && actual.changedNanoseconds == saved.changedNanoseconds),
                  evidence.sha256 == intent.sha256 else { return false }
            return BackupReadOnlyFiles.matches(root: root, relativePath: path, evidence: evidence)
        } catch is CancellationError { throw CancellationError() } catch { return false }
    }

    private static func hasOwnedStaging(root: BackupDescriptor, intent: BackupStagingIntent) throws -> Bool {
        let components = intent.stagingRelativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3, components.allSatisfy(BackupDescriptor.isComponent),
              components[0] == ".cloakroll-staging-" + intent.runID.uuidString.lowercased(),
              UUID(uuidString: components[1]) != nil else { return false }
        do {
            let directory = try root.directory(components[0])
            let marker = try directory.file(".owner")
            let status = try marker.status()
            let expected = Array(("CloakRoll original staging 1\n" + intent.runID.uuidString + "\n").utf8)
            guard (status.st_mode & S_IFMT) == S_IFREG, status.st_nlink == 1, status.st_size == expected.count else { return false }
            var bytes = [UInt8](repeating: 0, count: expected.count)
            let count = Darwin.read(marker.value, &bytes, bytes.count)
            return count == expected.count && bytes == expected
        } catch { return false }
    }
}

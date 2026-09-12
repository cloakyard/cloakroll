import Foundation
import ImageCaptureCore
import MediaModels
import OSLog

/// Serial, yielding normalization keeps framework handles on the main actor. The stream receives
/// complete accumulated values, so its newest-only buffering cannot discard resource deltas.
@MainActor
final class CameraCatalog {
    private struct Job {
        enum Kind { case upsert, remove, reconcile }
        let items: [ICCameraItem]
        let kind: Kind
        let percent: Int?
        let iCloudPhotosEnabled: Bool?
    }

    private let publish: (DeviceMediaSnapshot) -> Void
    private let logger = Logger(subsystem: "com.cloakroll.core", category: "MediaCatalog")
    private let registry = CaptureObjectRegistry<ICCameraFile>()
    private var records: [String: SourceMediaRecord] = [:]
    private var ancestors: [String: Set<ObjectIdentifier>] = [:]
    private var jobs: [Job] = []
    private var jobIndex = 0
    private var worker: Task<Void, Never>?
    private var publication: Task<Void, Never>?
    private var sessionID: UUID?
    private var deviceID = ""
    private var revision: UInt64 = 0
    private var state: MediaScanState = .scanning
    private var percent: Int?
    private var iCloudPhotosEnabled: Bool?
    private var isDirty = false
    private let batchSize = 128

    init(publish: @escaping (DeviceMediaSnapshot) -> Void) {
        self.publish = publish
    }

    func begin(sessionID: UUID, deviceID: String, percent: Int?, iCloudPhotosEnabled: Bool?) {
        cancelWork()
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.percent = percent
        self.iCloudPhotosEnabled = iCloudPhotosEnabled
        registry.begin(sessionID: sessionID)
        records.removeAll()
        ancestors.removeAll()
        revision = 0
        state = .scanning
        isDirty = true
        publishNow()
    }

    func add(_ items: [ICCameraItem], sessionID: UUID, percent: Int?, iCloudPhotosEnabled: Bool?) {
        enqueue(items, kind: .upsert, sessionID: sessionID, percent: percent, iCloudPhotosEnabled: iCloudPhotosEnabled)
    }

    func remove(_ items: [ICCameraItem], sessionID: UUID, percent: Int?, iCloudPhotosEnabled: Bool?) {
        enqueue(items, kind: .remove, sessionID: sessionID, percent: percent, iCloudPhotosEnabled: iCloudPhotosEnabled)
    }

    func complete(_ items: [ICCameraItem], sessionID: UUID, percent: Int?, iCloudPhotosEnabled: Bool?) {
        enqueue(items, kind: .reconcile, sessionID: sessionID, percent: percent, iCloudPhotosEnabled: iCloudPhotosEnabled)
    }

    func interrupt(sessionID: UUID) {
        guard self.sessionID == sessionID, registry.sessionID == sessionID else { return }
        cancelWork()
        registry.clear()
        ancestors.removeAll()
        state = .interrupted
        isDirty = true
        publishNow()
    }

    /// The caller must additionally verify its camera is currently readable before device I/O.
    func file(for resourceID: String, sessionID: UUID) throws -> ICCameraFile {
        try registry.object(for: resourceID, sessionID: sessionID)
    }

    private func enqueue(
        _ items: [ICCameraItem], kind: Job.Kind, sessionID: UUID,
        percent: Int?, iCloudPhotosEnabled: Bool?
    ) {
        guard registry.sessionID == sessionID else { return }
        jobs.append(Job(items: items, kind: kind, percent: percent, iCloudPhotosEnabled: iCloudPhotosEnabled))
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.processJobs(sessionID: sessionID) }
    }

    private func processJobs(sessionID: UUID) async {
        while jobIndex < jobs.count, isCurrent(sessionID) {
            let job = jobs[jobIndex]
            jobIndex += 1
            if job.kind == .remove {
                await removeItems(job.items, sessionID: sessionID)
            } else {
                await ingest(job.items, reconcile: job.kind == .reconcile, sessionID: sessionID)
            }
            guard isCurrent(sessionID) else { return }
            percent = job.percent
            iCloudPhotosEnabled = job.iCloudPhotosEnabled
            if job.kind == .reconcile { state = .complete }
            isDirty = true
            if job.kind == .reconcile { publishNow() } else { schedulePublication() }
            await Task.yield()
        }
        guard isCurrent(sessionID) else { return }
        jobs.removeAll(keepingCapacity: true)
        jobIndex = 0
        worker = nil
    }

    private func ingest(_ items: [ICCameraItem], reconcile: Bool, sessionID: UUID) async {
        var stack = [items.makeIterator()]
        var seen: Set<ObjectIdentifier> = []
        var found: Set<String> = []
        var processed = 0
        while !stack.isEmpty, isCurrent(sessionID) {
            guard let item = stack[stack.count - 1].next() else {
                stack.removeLast()
                continue
            }
            guard seen.insert(ObjectIdentifier(item)).inserted else { continue }
            if let folder = item as? ICCameraFolder {
                stack.append((folder.contents ?? []).makeIterator())
            } else if let file = item as? ICCameraFile {
                let identifier = registry.identifier(for: file)
                found.insert(identifier)
                let companions = (file.sidecarFiles ?? []).compactMap { $0 as? ICCameraFile }
                let sidecarIDs = companions.map { registry.identifier(for: $0) }
                let pairedRawID = file.pairedRawImage.map { registry.identifier(for: $0) }
                records[identifier] = CaptureRecordNormalizer.record(
                    for: file, id: identifier, deviceID: deviceID,
                    sidecarIDs: Array(Set(sidecarIDs)).sorted(), pairedRawID: pairedRawID
                )
                ancestors[identifier] = CaptureRecordNormalizer.context(for: file).ancestors
                var related: [ICCameraItem] = companions
                if let raw = file.pairedRawImage { related.append(raw) }
                if !related.isEmpty { stack.append(related.makeIterator()) }
            }
            processed += 1
            if processed.isMultiple(of: batchSize) {
                isDirty = true
                schedulePublication()
                await Task.yield()
            }
        }
        guard reconcile, isCurrent(sessionID) else { return }
        let missing = Set(records.keys).subtracting(found)
        await removeIDs(missing, sessionID: sessionID)
    }

    private func removeItems(_ items: [ICCameraItem], sessionID: UUID) async {
        let keys = Set(items.map(ObjectIdentifier.init))
        var removed = Set(items.compactMap { item in
            (item as? ICCameraFile).flatMap { registry.existingIdentifier(for: $0) }
        })
        let knownAncestors = ancestors
        var processed = 0
        for (identifier, parents) in knownAncestors {
            guard isCurrent(sessionID) else { return }
            if !parents.isDisjoint(with: keys) { removed.insert(identifier) }
            processed += 1
            if processed.isMultiple(of: batchSize) { await Task.yield() }
        }
        await removeIDs(removed, sessionID: sessionID)
    }

    private func removeIDs(_ identifiers: Set<String>, sessionID: UUID) async {
        var processed = 0
        for identifier in identifiers {
            guard isCurrent(sessionID) else { return }
            records[identifier] = nil
            ancestors[identifier] = nil
            registry.remove(identifier)
            processed += 1
            if processed.isMultiple(of: batchSize) { await Task.yield() }
        }
    }

    private func isCurrent(_ sessionID: UUID) -> Bool {
        !Task.isCancelled && registry.sessionID == sessionID
    }

    private func schedulePublication() {
        guard publication == nil else { return }
        let token = sessionID
        publication = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.sessionID == token else { return }
            self.publication = nil
            self.publishNow()
        }
    }

    private func publishNow() {
        publication?.cancel()
        publication = nil
        guard isDirty, let sessionID else { return }
        isDirty = false
        revision += 1
        publish(DeviceMediaSnapshot(
            sessionID: sessionID, deviceID: deviceID, revision: revision, records: Array(records.values),
            state: state, percentComplete: percent, iCloudPhotosEnabled: iCloudPhotosEnabled
        ))
        if state != .scanning {
            logger.info("Camera catalog \(self.state.rawValue, privacy: .public); resources: \(self.records.count, privacy: .public)")
        }
    }

    private func cancelWork() {
        worker?.cancel()
        worker = nil
        publication?.cancel()
        publication = nil
        jobs.removeAll()
        jobIndex = 0
    }

    deinit {
        worker?.cancel()
        publication?.cancel()
    }
}

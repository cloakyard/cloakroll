import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Conservative original backup identity")
struct BackupIdentityIndexTests {
    private let phone = DeviceIdentity(kind: .persistent, value: "phone")
    private let session = UUID()

    @Test func reconnectChangesHandlesWithoutChangingOriginalEvidence() throws {
        let old = [record("old-still", sidecars: ["old-movie"]), movie("old-movie")]
        let new = [movie("new-movie"), record("new-still", sidecars: ["new-movie"])]
        let first = try onlyAsset(make(old))
        let next = try onlyAsset(make(new, sessionID: UUID()))
        #expect(first.assetID != next.assetID)
        #expect(first.isReusableAcrossConnections && next.isReusableAcrossConnections)
        #expect(first.canonical == next.canonical)
        #expect(first.digest == next.digest)
        #expect(first.resources["old-still"]?.canonical == next.resources["new-still"]?.canonical)
        #expect(first.resources["old-movie"]?.digest == next.resources["new-movie"]?.digest)
        #expect(!first.canonical.contains("old-still"))
        #expect(!first.canonical.contains(phone.key))
        #expect(first.digest.count == 64)
    }

    @Test func catalogAndCompanionOrderingDoNotChangeIdentity() throws {
        let records = [record("still", sidecars: ["movie", "sidecar"]), movie("movie"), sidecar("sidecar")]
        let assets = CatalogAssembler.assemble(records: records)
        let original = try make(records, assets: assets)
        let reversed = assets.map { asset in
            MediaAsset(
                id: asset.id, deviceID: asset.deviceID, resources: asset.resources.reversed(), kind: asset.kind,
                createdAt: asset.createdAt, duration: asset.duration, pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight, primaryResourceID: asset.primaryResourceID
            )
        }
        #expect(try make(records.reversed(), assets: reversed) == original)
    }

    @Test func persistentIdentityKindAndValueScopeEveryCatalog() throws {
        let identities = [phone, DeviceIdentity(kind: .serialNumber, value: "phone"),
                          DeviceIdentity(kind: .persistent, value: "another-phone")]
        var keys: Set<String> = []
        for identity in identities {
            let value = try make([record("one", device: identity.key)], identity: identity)
            keys.insert(value.deviceKey)
            #expect(try onlyAsset(value).isReusableAcrossConnections)
        }
        #expect(keys.count == identities.count)
        let mismatch = try make([record("one")], identity: identities[1])
        #expect(try !onlyAsset(mismatch).isReusableAcrossConnections)
    }

    @Test func missingAndSessionOnlyDeviceIdentityNeverCrossConnections() throws {
        let temporary = DeviceIdentity(kind: .sessionOnly, value: "phone")
        let records = [record("one", device: temporary.key)]
        let first = try onlyAsset(make(records, identity: temporary))
        let repeated = try onlyAsset(make(records, identity: temporary))
        let reconnect = try onlyAsset(make(records, identity: temporary, sessionID: UUID()))
        #expect(!first.isReusableAcrossConnections)
        #expect(first.canonical == repeated.canonical)
        #expect(first.canonical != reconnect.canonical)
        #expect(try !onlyAsset(make([record("one")], identity: nil)).isReusableAcrossConnections)
    }

    @Test func duplicateOriginalEvidenceKeepsEveryCandidateConnectionScoped() throws {
        let result = try make([record("one"), record("two"), record("unique", filename: "OTHER.HEIC")])
        let duplicates = result.assets.values.filter { !$0.isReusableAcrossConnections }
        #expect(duplicates.count == 2)
        #expect(Set(duplicates.map(\.canonical)).count == 2)
        #expect(result.assets.values.filter(\.isReusableAcrossConnections).count == 1)
        #expect(duplicates.allSatisfy { $0.resources.values.allSatisfy { !$0.isReusableAcrossConnections } })
    }

    @Test func duplicateSourceHandlesAreNeverReusable() throws {
        let result = try make([record("same"), record("same", filename: "OTHER.HEIC")])
        #expect(result.assets.count == 2)
        #expect(result.assets.values.allSatisfy { !$0.isReusableAcrossConnections })
    }

    @Test func ambiguousSourceRelationshipChangesInvalidateSameSessionFallback() throws {
        let first = try make([record("same"), record("same", filename: "OTHER.HEIC")])
        let changed = try make([record("same", sidecars: ["missing"]), record("same", filename: "OTHER.HEIC")])
        #expect(Set(first.assets.values.map(\.digest)).isDisjoint(with: Set(changed.assets.values.map(\.digest))))
        #expect(changed.assets.values.allSatisfy { !$0.isReusableAcrossConnections })
    }

    @Test func insufficientEvidenceRemainsExplicitlyConnectionScoped() throws {
        let cases = [
            record("one", createdAt: nil), record("one", context: []), record("one", context: ["DCIM", " "]),
            record("one", byteCount: 0), record("one", uti: nil),
            record("one", createdAt: Date(timeIntervalSince1970: .infinity)),
            record("one", modifiedAt: Date(timeIntervalSince1970: .nan))
        ]
        for item in cases {
            let first = try onlyAsset(make([item]))
            let reconnect = try onlyAsset(make([item], sessionID: UUID()))
            #expect(!first.isReusableAcrossConnections)
            #expect(first.canonical != reconnect.canonical)
            #expect(!first.resources.isEmpty)
        }
    }

    @Test func companionChangesInvalidateEveryResourceIncludingUnchangedStill() throws {
        let first = try onlyAsset(make([record("still", sidecars: ["movie"]), movie("movie")]))
        let changed = try onlyAsset(make([record("still", sidecars: ["movie"]), movie("movie", byteCount: 201)]))
        #expect(first.canonical != changed.canonical)
        #expect(first.resources["still"]?.digest != changed.resources["still"]?.digest)
        #expect(first.resources["movie"]?.digest != changed.resources["movie"]?.digest)
        let added = try onlyAsset(make([
            record("still", sidecars: ["movie", "sidecar"]), movie("movie"), sidecar("sidecar")
        ]))
        #expect(first.resources["still"]?.digest != added.resources["still"]?.digest)
        #expect(added.isReusableAcrossConnections)
    }

    @Test func relationshipEvidenceChangesEvenWhenMembershipDoesNot() throws {
        let first = try onlyAsset(make([record("still", sidecars: ["movie"], origin: "pair"), movie("movie", origin: "pair")]))
        let next = try onlyAsset(make([record("still", origin: "pair"), movie("movie", origin: "pair")]))
        #expect(first.isReusableAcrossConnections && next.isReusableAcrossConnections)
        #expect(first.resources.count == next.resources.count)
        #expect(first.canonical != next.canonical)
    }

    @Test func missingOrExternalRelationshipTargetsDisableReuse() throws {
        let missing = try onlyAsset(make([record("still", sidecars: ["missing"])]))
        #expect(!missing.isReusableAcrossConnections)
        let external = try make([record("one", sidecars: ["two"]), record("two", filename: "OTHER.HEIC")])
        #expect(external.assets.values.allSatisfy { !$0.isReusableAcrossConnections || $0.resources.keys.contains("two") })
        let source = try #require(external.assets.values.first { $0.resources["one"] != nil })
        #expect(!source.isReusableAcrossConnections)
    }

    @Test func originalRepresentationFactsAreNeverInterchangeable() throws {
        let original = try onlyAsset(make([record("one")]))
        let variants = [
            record("one", filename: "IMG.JPG", uti: "public.jpeg"),
            record("one", originalFilename: "different.HEIC"),
            record("one", context: ["DCIM/100APPLE"]),
            record("one", isRaw: true), record("one", group: "group"), record("one", related: "related"),
            record("one", burst: "burst"), record("one", modifiedAt: Date(timeIntervalSince1970: 1_700_000_002))
        ]
        for variant in variants {
            #expect(try onlyAsset(make([variant])).canonical != original.canonical)
        }
        #expect(original.canonical.contains("originalAssets"))
    }

    @Test func filenameAloneDoesNotCollapseDistinctOriginals() throws {
        let result = try make([record("first"), record("second", byteCount: 201)])
        #expect(result.assets.count == 2)
        #expect(result.assets.values.allSatisfy { $0.isReusableAcrossConnections })
        #expect(Set(result.assets.values.map(\.canonical)).count == 2)
    }

    @Test func changedPrimaryComponentInvalidatesLogicalAssetAndAllResources() throws {
        let records = [record("still", sidecars: ["movie"]), movie("movie")]
        let asset = try #require(CatalogAssembler.assemble(records: records).first)
        let changedPrimary = MediaAsset(
            id: asset.id, deviceID: asset.deviceID, resources: asset.resources, kind: asset.kind,
            createdAt: asset.createdAt, duration: asset.duration, pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight, primaryResourceID: "movie"
        )
        let first = try onlyAsset(make(records, assets: [asset]))
        let next = try onlyAsset(make(records, assets: [changedPrimary]))
        #expect(first.canonical != next.canonical)
        #expect(first.resources["still"]?.canonical != next.resources["still"]?.canonical)
    }

    @Test func newItemsDoNotInvalidateExistingUnambiguousEvidence() throws {
        let first = try onlyAsset(make([record("old")]))
        let result = try make([record("renamed-handle"), record("new", filename: "NEW.HEIC")], sessionID: UUID())
        let existing = try #require(result.assets.values.first { $0.resources["renamed-handle"] != nil })
        #expect(existing.canonical == first.canonical)
        #expect(result.assets.values.allSatisfy { $0.isReusableAcrossConnections })
        #expect(try JSONDecoder().decode(BackupCatalogIdentity.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test func incompleteAndForeignDeviceCatalogsAreRejected() throws {
        let incomplete = DeviceMediaSnapshot(sessionID: session, deviceID: phone.key, revision: 1, records: [], state: .scanning)
        #expect(throws: BackupIdentityError.incompleteCatalog) {
            try BackupIdentityIndex.make(source: incomplete, assets: [], deviceIdentity: phone)
        }
        let foreign = DeviceMediaSnapshot(
            sessionID: session, deviceID: phone.key, revision: 1,
            records: [record("foreign", device: "persistent:other")], state: .complete
        )
        #expect(throws: BackupIdentityError.inconsistentCatalog) {
            try BackupIdentityIndex.make(source: foreign, assets: [], deviceIdentity: phone)
        }
    }

    @Test func cancelledConstructionRejectsRatherThanPublishingPartialIndex() async throws {
        let records = (0..<2_000).map { record("id-\($0)", filename: "IMG_\($0).HEIC") }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try make(records)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func make(
        _ records: [SourceMediaRecord], identity: DeviceIdentity? = DeviceIdentity(kind: .persistent, value: "phone"),
        sessionID: UUID? = nil, assets: [MediaAsset]? = nil
    ) throws -> BackupCatalogIdentity {
        try BackupIdentityIndex.make(
            source: DeviceMediaSnapshot(
                sessionID: sessionID ?? session, deviceID: records.first?.deviceID ?? phone.key,
                revision: 1, records: records, state: .complete
            ), assets: assets ?? CatalogAssembler.assemble(records: records), deviceIdentity: identity
        )
    }

    private func onlyAsset(_ catalog: BackupCatalogIdentity) throws -> BackupAssetIdentity {
        #expect(catalog.assets.count == 1)
        return try #require(catalog.assets.values.first)
    }

    private func record(
        _ id: String, device: String = "persistent:phone", filename: String = "IMG.HEIC",
        originalFilename: String? = nil, context: [String] = ["DCIM", "100APPLE"],
        byteCount: Int64 = 200, uti: String? = "public.heic", isRaw: Bool = false,
        createdAt: Date? = Date(timeIntervalSince1970: 1_700_000_000), modifiedAt: Date? = nil,
        sidecars: [String] = [], origin: String? = nil, group: String? = nil, related: String? = nil, burst: String? = nil
    ) -> SourceMediaRecord {
        SourceMediaRecord(
            id: id, deviceID: device, filename: filename, originalFilename: originalFilename, contextPath: context,
            uti: uti, isRaw: isRaw, byteCount: byteCount, createdAt: createdAt, modifiedAt: modifiedAt,
            pixelWidth: 4000, pixelHeight: 3000, originatingAssetID: origin, groupUUID: group,
            relatedUUID: related, burstUUID: burst, sidecarIDs: sidecars
        )
    }

    private func movie(_ id: String, byteCount: Int64 = 200, origin: String? = nil) -> SourceMediaRecord {
        record(id, filename: "IMG.MOV", byteCount: byteCount, uti: "com.apple.quicktime-movie", origin: origin)
    }

    private func sidecar(_ id: String) -> SourceMediaRecord {
        record(id, filename: "IMG.AAE", uti: "com.apple.property-list")
    }
}

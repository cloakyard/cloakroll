#if DEBUG
import MediaModels

/// Native UI review fixtures. These never address an iPhone or a backup destination.
enum MediaInfoExamples {
    case longFilenames, missingMetadata

    @MainActor static func show(_ example: Self, in model: AppModel) async {
        await model.loadSample(count: 20)
        guard model.isSample, !model.backup.isBusy else { return }
        model.infoAsset = example.asset
    }

    private var asset: MediaAsset {
        switch self {
        case .longFilenames:
            MediaAsset(
                id: "fixture-0", deviceID: "info-example", resources: (1...30).map { index in
                    MediaResource(
                        id: "info-original-\(index)",
                        filename: "Journey_山と海_OriginalPhotographWithAnUnusuallyLongFilename_2026_10_04_\(index).HEIC",
                        byteCount: 2_700_000
                    )
                }, kind: .photo, createdAt: nil, pixelWidth: 4_032, pixelHeight: 3_024
            )
        case .missingMetadata:
            MediaAsset(id: "missing-info-example", deviceID: "info-example", resources: [], kind: .other, createdAt: nil)
        }
    }
}
#endif

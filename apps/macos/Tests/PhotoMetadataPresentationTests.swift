import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Camera metadata presentation")
struct PhotoMetadataPresentationTests {
    private let english = Locale(identifier: "en_US")

    @Test("Common reciprocal shutter speeds retain their photographic notation")
    func reciprocalShutterSpeeds() {
        #expect(PhotoMetadataPresentation.shutterSpeed(1.0 / 60, locale: english) == "1/60 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(1.0 / 71, locale: english) == "1/71 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(1.0 / 1_000, locale: english) == "1/1000 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(0.5, locale: english) == "1/2 s")
    }

    @Test("Non-reciprocal and long exposures preserve their measured duration")
    func decimalShutterSpeeds() {
        #expect(PhotoMetadataPresentation.shutterSpeed(0.6, locale: english) == "0.6 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(1, locale: english) == "1 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(2.5, locale: english) == "2.5 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(30, locale: english) == "30 s")
    }

    @Test("Invalid exposure durations are omitted rather than formatted as a measurement")
    func invalidShutterSpeeds() {
        for duration in [0, -0.0, -0.6, Double.nan, .infinity, -.infinity] {
            #expect(PhotoMetadataPresentation.shutterSpeed(duration, locale: english) == nil)
        }
    }

    @Test("A complete metadata value produces labeled camera facts in reading order")
    func completeMetadata() {
        let metadata = PhotoCameraMetadata(
            cameraMake: "Apple", cameraModel: "iPhone 16 Pro", lensModel: "Main Camera",
            iso: 100, apertureFNumber: 1.78, exposureTime: 1.0 / 60,
            focalLength: 6.765, focalLength35mm: 24, exposureBias: 1.0 / 3
        )
        #expect(PhotoMetadataPresentation.fields(for: metadata, locale: english) == [
            .init(label: "Camera", value: "Apple iPhone 16 Pro"),
            .init(label: "Lens", value: "Main Camera"),
            .init(label: "ISO", value: "100"),
            .init(label: "Aperture", value: "ƒ/1.78"),
            .init(label: "Shutter speed", value: "1/60 s"),
            .init(label: "Focal length", value: "6.765 mm"),
            .init(label: "35 mm equivalent", value: "24 mm"),
            .init(label: "Exposure bias", value: "+0.33 EV")
        ])
    }

    @Test("Partial metadata omits missing facts without fabricating fallback measurements")
    func partialMetadata() {
        let fields = PhotoMetadataPresentation.fields(
            for: PhotoCameraMetadata(lensModel: "  Telephoto \n", iso: 640), locale: english
        )
        #expect(fields == [.init(label: "Lens", value: "Telephoto"), .init(label: "ISO", value: "640")])
        #expect(Set(fields.map(\.id)).count == fields.count)
        #expect(PhotoMetadataPresentation.fields(for: PhotoCameraMetadata(), locale: english).isEmpty)
    }

    @Test("Camera make and model are trimmed, combined, and deduplicated without dropping model identity")
    func cameraNames() {
        let cases: [(String?, String?, String?)] = [
            (" Apple \n", " iPhone 16 Pro ", "Apple iPhone 16 Pro"),
            ("Canon", "Canon EOS R5", "Canon EOS R5"),
            ("CANON", "canon EOS R5", "canon EOS R5"),
            ("Canon", "canon", "canon"),
            ("Canon", "Canonicals 7", "Canon Canonicals 7"),
            (nil, "iPhone 16 Pro", "iPhone 16 Pro"),
            ("Apple", nil, "Apple"),
            ("  \n", "iPhone 16 Pro", "iPhone 16 Pro"),
            ("  ", "\n", nil)
        ]
        for (make, model, expected) in cases {
            let fields = PhotoMetadataPresentation.fields(
                for: PhotoCameraMetadata(cameraMake: make, cameraModel: model), locale: english
            )
            #expect(fields.first?.value == expected)
            #expect(fields.count == (expected == nil ? 0 : 1))
        }
    }

    @Test("Invalid numeric facts and blank text are absent while zero exposure bias remains meaningful")
    func invalidFacts() {
        for value in [0, -1, Double.nan, .infinity, -.infinity] {
            let metadata = PhotoCameraMetadata(
                cameraMake: " ", cameraModel: "\n", lensModel: " \t ", iso: 0,
                apertureFNumber: value, exposureTime: value, focalLength: value,
                focalLength35mm: value, exposureBias: .nan
            )
            #expect(PhotoMetadataPresentation.fields(for: metadata, locale: english).isEmpty)
        }
        #expect(PhotoMetadataPresentation.fields(for: PhotoCameraMetadata(iso: -100), locale: english).isEmpty)
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(PhotoMetadataPresentation.fields(
                for: PhotoCameraMetadata(exposureBias: value), locale: english
            ).isEmpty)
        }
        #expect(PhotoMetadataPresentation.fields(for: PhotoCameraMetadata(exposureBias: 0), locale: english) == [
            .init(label: "Exposure bias", value: "0 EV")
        ])
    }

    @Test("Decimal measurements honor the supplied locale without changing units or integer exposure denominators")
    func localizedDecimals() {
        let german = Locale(identifier: "de_DE")
        #expect(PhotoMetadataPresentation.shutterSpeed(0.6, locale: german) == "0,6 s")
        #expect(PhotoMetadataPresentation.shutterSpeed(1.0 / 1_000, locale: german) == "1/1000 s")
        let fields = PhotoMetadataPresentation.fields(
            for: PhotoCameraMetadata(
                apertureFNumber: 1.8, focalLength: 6.75, focalLength35mm: 24.5, exposureBias: -0.67
            ), locale: german
        )
        #expect(fields == [
            .init(label: "Aperture", value: "ƒ/1,8"),
            .init(label: "Focal length", value: "6,75 mm"),
            .init(label: "35 mm equivalent", value: "24,5 mm"),
            .init(label: "Exposure bias", value: "-0,67 EV")
        ])
    }

    @Test("Exposure compensation distinguishes positive, negative and neutral values")
    func signedExposureBias() {
        for (value, expected) in [(1.0 / 3, "+0.33 EV"), (-2.0 / 3, "-0.67 EV"), (2, "+2 EV"), (0, "0 EV")] {
            let fields = PhotoMetadataPresentation.fields(
                for: PhotoCameraMetadata(exposureBias: value), locale: english
            )
            #expect(fields == [.init(label: "Exposure bias", value: expected)])
        }
    }
}

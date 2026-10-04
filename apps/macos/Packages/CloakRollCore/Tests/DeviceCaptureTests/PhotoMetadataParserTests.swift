import Foundation
import ImageIO
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Photo camera metadata")
struct PhotoMetadataParserTests {
    @Test func readsCameraFactsFromOfficialImageIODictionaries() {
        let value = PhotoMetadataParser.parse([
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: " Apple ",
                kCGImagePropertyTIFFModel as String: "iPhone 16 Pro"
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: "iPhone back camera",
                kCGImagePropertyExifISOSpeedRatings as String: [80],
                kCGImagePropertyExifFNumber as String: 1.78,
                kCGImagePropertyExifExposureTime as String: 1.0 / 125,
                kCGImagePropertyExifFocalLength as String: 6.765,
                kCGImagePropertyExifFocalLenIn35mmFilm as String: 24,
                kCGImagePropertyExifExposureBiasValue as String: -1.0 / 3
            ]
        ])
        #expect(value == PhotoCameraMetadata(
            cameraMake: "Apple", cameraModel: "iPhone 16 Pro", lensModel: "iPhone back camera",
            iso: 80, apertureFNumber: 1.78, exposureTime: 1.0 / 125,
            focalLength: 6.765, focalLength35mm: 24, exposureBias: -1.0 / 3
        ))
        #expect(!value.isEmpty)
    }

    @Test func acceptsFoundationDictionaryArrayStringAndNumberBridges() {
        let dictionary: NSDictionary = [
            kCGImagePropertyTIFFDictionary as String: NSDictionary(dictionary: [
                kCGImagePropertyTIFFMake as String: NSString(string: "Apple"),
                kCGImagePropertyTIFFModel as String: NSString(string: "Camera")
            ]),
            kCGImagePropertyExifDictionary as String: NSDictionary(dictionary: [
                kCGImagePropertyExifISOSpeedRatings as String: NSArray(array: [NSNumber(value: 200)]),
                kCGImagePropertyExifFNumber as String: NSDecimalNumber(string: "2.8"),
                kCGImagePropertyExifExposureTime as String: NSNumber(value: 1.0 / 250),
                kCGImagePropertyExifExposureBiasValue as String: NSNumber(value: 0)
            ])
        ]
        let value = PhotoMetadataParser.parse(dictionary as? [AnyHashable: Any])
        #expect(value == PhotoCameraMetadata(
            cameraMake: "Apple", cameraModel: "Camera", iso: 200,
            apertureFNumber: 2.8, exposureTime: 1.0 / 250, exposureBias: 0
        ))
    }

    @Test func missingAndUnrelatedMetadataStayEmpty() {
        #expect(PhotoMetadataParser.parse(nil).isEmpty)
        #expect(PhotoMetadataParser.parse([:]).isEmpty)
        #expect(PhotoMetadataParser.parse([
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 12.3],
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2026:10:04 12:30:00"]
        ]).isEmpty)
    }

    @Test func partialMetadataAndZeroExposureBiasRemainMeaningful() {
        #expect(PhotoMetadataParser.parse(exif([kCGImagePropertyExifExposureBiasValue as String: 0]))
            == PhotoCameraMetadata(exposureBias: 0))
        #expect(!PhotoCameraMetadata(exposureBias: 0).isEmpty)
        #expect(PhotoMetadataParser.parse([
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFModel as String: "Camera only"]
        ]) == PhotoCameraMetadata(cameraModel: "Camera only"))
    }

    @Test func malformedContainersAndTextNumbersAreNotCoerced() {
        #expect(PhotoMetadataParser.parse([
            kCGImagePropertyTIFFDictionary as String: "Apple",
            kCGImagePropertyExifDictionary as String: [1, 2]
        ]).isEmpty)
        #expect(PhotoMetadataParser.parse(exif([
            kCGImagePropertyExifLensModel as String: 42,
            kCGImagePropertyExifISOSpeedRatings as String: "100",
            kCGImagePropertyExifFNumber as String: "2.8",
            kCGImagePropertyExifExposureTime as String: "1/125",
            kCGImagePropertyExifFocalLength as String: [24, 1],
            kCGImagePropertyExifFocalLenIn35mmFilm as String: NSNull(),
            kCGImagePropertyExifExposureBiasValue as String: "0"
        ])).isEmpty)
    }

    @Test func booleansAreNeverCameraMeasurements() {
        #expect(PhotoMetadataParser.parse(exif([
            kCGImagePropertyExifISOSpeedRatings as String: [true],
            kCGImagePropertyExifISOSpeed as String: NSNumber(value: false),
            kCGImagePropertyExifFNumber as String: true,
            kCGImagePropertyExifExposureTime as String: NSNumber(value: true),
            kCGImagePropertyExifFocalLength as String: false,
            kCGImagePropertyExifFocalLenIn35mmFilm as String: true,
            kCGImagePropertyExifExposureBiasValue as String: NSNumber(value: false)
        ])).isEmpty)
        #expect(PhotoMetadataParser.parse(exif([kCGImagePropertyExifFNumber as String: NSNumber(value: Int8(1))]))
            == PhotoCameraMetadata(apertureFNumber: 1))
    }

    @Test func rejectsInvalidPhysicalValuesAndNonfiniteBias() {
        for value in [0.0, -1, Double.nan, .infinity, -.infinity] {
            let metadata = PhotoMetadataParser.parse(exif([
                kCGImagePropertyExifISOSpeedRatings as String: [value],
                kCGImagePropertyExifFNumber as String: value,
                kCGImagePropertyExifExposureTime as String: value,
                kCGImagePropertyExifFocalLength as String: value,
                kCGImagePropertyExifFocalLenIn35mmFilm as String: value
            ]))
            #expect(metadata.isEmpty)
        }
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(PhotoMetadataParser.parse(exif([kCGImagePropertyExifExposureBiasValue as String: value])).isEmpty)
        }
    }

    @Test func isoUsesWholePositiveValuesAndSupportedFallback() {
        #expect(PhotoMetadataParser.parse(exif([kCGImagePropertyExifISOSpeedRatings as String: [NSNull(), true, -1, 80, 160]]))
            .iso == 80)
        #expect(PhotoMetadataParser.parse(exif([kCGImagePropertyExifISOSpeedRatings as String: NSNumber(value: 320)])).iso == 320)
        #expect(PhotoMetadataParser.parse(exif([
            kCGImagePropertyExifISOSpeedRatings as String: [],
            kCGImagePropertyExifISOSpeed as String: 640
        ])).iso == 640)
        for value in [0.5, 80.5, Double(Int.max), Double.greatestFiniteMagnitude] {
            #expect(PhotoMetadataParser.parse(exif([kCGImagePropertyExifISOSpeedRatings as String: [value]])).iso == nil)
        }
    }

    @Test func preservesFractionalMeasurementsRatherThanTruncatingOrApplyingAPEX() {
        #expect(PhotoMetadataParser.parse(exif([
            kCGImagePropertyExifExposureTime as String: 2.5,
            kCGImagePropertyExifFNumber as String: 1.6,
            kCGImagePropertyExifFocalLength as String: 4.25,
            kCGImagePropertyExifExposureBiasValue as String: 2.0 / 3
        ])) == PhotoCameraMetadata(apertureFNumber: 1.6, exposureTime: 2.5, focalLength: 4.25, exposureBias: 2.0 / 3))
        #expect(PhotoMetadataParser.parse(exif([
            kCGImagePropertyExifApertureValue as String: 2,
            kCGImagePropertyExifShutterSpeedValue as String: 7
        ])).isEmpty)
    }

    @Test func textIsTrimmedAndBoundedWithoutBreakingUnicodeCharacters() {
        let metadata = PhotoMetadataParser.parse([
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: " \n\t\0 ",
                kCGImagePropertyTIFFModel as String: " \nCamera 📷\0 "
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: String(repeating: "e\u{301}", count: 300)
            ]
        ])
        #expect(metadata.cameraMake == nil)
        #expect(metadata.cameraModel == "Camera 📷")
        #expect(metadata.lensModel == String(repeating: "e\u{301}", count: 256))
    }

    @Test func parserCanProduceSendableFactsAwayFromMainActor() async {
        let metadata = await Task.detached {
            PhotoMetadataParser.parse([
                kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifISOSpeedRatings as String: [100]]
            ])
        }.value
        #expect(metadata == PhotoCameraMetadata(iso: 100))
    }

    private func exif(_ values: [String: Any]) -> [AnyHashable: Any] {
        [kCGImagePropertyExifDictionary as String: values]
    }
}

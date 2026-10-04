import CoreFoundation
import Foundation
import ImageIO
import MediaModels

/// Converts framework-owned dictionaries to Sendable facts on the callback's current queue.
/// ImageIO supplies EXIF rational values as numbers; strings and guessed APEX conversions are ignored.
enum PhotoMetadataParser {
    static func parse(_ dictionary: [AnyHashable: Any]?) -> PhotoCameraMetadata {
        let exif = dictionary?[kCGImagePropertyExifDictionary as String] as? [AnyHashable: Any] ?? [:]
        let tiff = dictionary?[kCGImagePropertyTIFFDictionary as String] as? [AnyHashable: Any] ?? [:]
        return PhotoCameraMetadata(
            cameraMake: text(tiff[kCGImagePropertyTIFFMake as String]),
            cameraModel: text(tiff[kCGImagePropertyTIFFModel as String]),
            lensModel: text(exif[kCGImagePropertyExifLensModel as String]),
            iso: iso(exif[kCGImagePropertyExifISOSpeedRatings as String])
                ?? positiveInteger(exif[kCGImagePropertyExifISOSpeed as String]),
            apertureFNumber: positiveNumber(exif[kCGImagePropertyExifFNumber as String]),
            exposureTime: positiveNumber(exif[kCGImagePropertyExifExposureTime as String]),
            focalLength: positiveNumber(exif[kCGImagePropertyExifFocalLength as String]),
            focalLength35mm: positiveNumber(exif[kCGImagePropertyExifFocalLenIn35mmFilm as String]),
            exposureBias: number(exif[kCGImagePropertyExifExposureBiasValue as String])
        )
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : String(trimmed.prefix(256))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }

    private static func positiveNumber(_ value: Any?) -> Double? {
        guard let result = number(value), result > 0 else { return nil }
        return result
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        guard let result = positiveNumber(value) else { return nil }
        return Int(exactly: result)
    }

    private static func iso(_ value: Any?) -> Int? {
        if let values = value as? [Any] {
            return values.lazy.compactMap(positiveInteger).first
        }
        return positiveInteger(value)
    }
}

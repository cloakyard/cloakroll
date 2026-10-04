import Foundation
import MediaModels

enum PhotoMetadataPresentation {
    struct Field: Identifiable, Equatable {
        let label: String
        let value: String
        var id: String { label }
    }

    static func fields(for metadata: PhotoCameraMetadata, locale: Locale = .current) -> [Field] {
        var fields: [Field] = []
        func append(_ label: String, _ value: String?) {
            if let value { fields.append(Field(label: label, value: value)) }
        }
        append("Camera", cameraName(make: metadata.cameraMake, model: metadata.cameraModel))
        append("Lens", cleaned(metadata.lensModel))
        if let iso = metadata.iso, iso > 0 { append("ISO", String(iso)) }
        if let value = positive(metadata.apertureFNumber) {
            append("Aperture", "ƒ/\(decimal(value, locale: locale))")
        }
        append("Shutter speed", metadata.exposureTime.flatMap { shutterSpeed($0, locale: locale) })
        if let value = positive(metadata.focalLength) {
            append("Focal length", "\(decimal(value, locale: locale, fractionDigits: 3)) mm")
        }
        if let value = positive(metadata.focalLength35mm) {
            append("35 mm equivalent", "\(decimal(value, locale: locale)) mm")
        }
        if let value = metadata.exposureBias, value.isFinite {
            append("Exposure bias", "\(value > 0 ? "+" : "")\(decimal(value, locale: locale)) EV")
        }
        return fields
    }

    static func shutterSpeed(_ seconds: Double, locale: Locale = .current) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let reciprocal = 1 / seconds
        let denominator = reciprocal.rounded()
        // Preserve non-reciprocal exposures such as 0.6 s; avoid rounding them to 1/2 s.
        if seconds < 1, reciprocal.isFinite, denominator <= 1e12,
           abs(reciprocal - denominator) / reciprocal < 0.005 {
            return "1/\(denominator.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0)))) s"
        }
        return "\(seconds.formatted(.number.locale(locale).grouping(.never).precision(.significantDigits(1...4)))) s"
    }

    private static func cameraName(make: String?, model: String?) -> String? {
        let make = cleaned(make)
        let model = cleaned(model)
        guard let make, let model else { return model ?? make }
        if model.compare(make, options: .caseInsensitive) == .orderedSame
            || model.lowercased().hasPrefix(make.lowercased() + " ") { return model }
        return "\(make) \(model)"
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func positive(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private static func decimal(_ value: Double, locale: Locale, fractionDigits: Int = 2) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...fractionDigits)))
    }
}

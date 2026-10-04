import Foundation

/// Optional camera facts supplied by a photo's metadata, without location data or display formatting.
public struct PhotoCameraMetadata: Equatable, Sendable {
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let iso: Int?
    public let apertureFNumber: Double?
    public let exposureTime: Double?
    public let focalLength: Double?
    public let focalLength35mm: Double?
    public let exposureBias: Double?

    public init(
        cameraMake: String? = nil, cameraModel: String? = nil, lensModel: String? = nil,
        iso: Int? = nil, apertureFNumber: Double? = nil, exposureTime: Double? = nil,
        focalLength: Double? = nil, focalLength35mm: Double? = nil, exposureBias: Double? = nil
    ) {
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.iso = iso
        self.apertureFNumber = apertureFNumber
        self.exposureTime = exposureTime
        self.focalLength = focalLength
        self.focalLength35mm = focalLength35mm
        self.exposureBias = exposureBias
    }

    public var isEmpty: Bool {
        cameraMake == nil && cameraModel == nil && lensModel == nil && iso == nil
            && apertureFNumber == nil && exposureTime == nil && focalLength == nil
            && focalLength35mm == nil && exposureBias == nil
    }
}

@MainActor
public protocol PhotoMetadataProviding: AnyObject {
    func photoMetadata(for resourceID: String, sessionID: UUID) async throws -> PhotoCameraMetadata
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CloakRoll

struct ThumbnailDecoderTests {
    @Test func decodingBoundsPixelMemoryAndPreservesAspect() async throws {
        let data = try makeImage(orientation: 1)
        let image = await Task.detached { ThumbnailDecoder.decode(data, maximumPixelSize: 128) }.value
        let decoded = try #require(image)
        #expect(decoded.width == 128)
        #expect(decoded.height == 64)
    }

    @Test func thumbnailRespectsSourceOrientation() async throws {
        let data = try makeImage(orientation: 6)
        let image = await Task.detached { ThumbnailDecoder.decode(data, maximumPixelSize: 128) }.value
        let decoded = try #require(image)
        #expect(decoded.width == 64)
        #expect(decoded.height == 128)
    }

    @Test func invalidImageDataKeepsThePlaceholderAvailable() {
        #expect(ThumbnailDecoder.decode(Data("not an image".utf8), maximumPixelSize: 128) == nil)
    }

    private func makeImage(orientation: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 640, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

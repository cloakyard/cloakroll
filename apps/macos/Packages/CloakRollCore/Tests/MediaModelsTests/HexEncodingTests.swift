import CryptoKit
import Foundation
import MediaModels
import Testing

@Suite("Persisted hexadecimal compatibility")
struct HexEncodingTests {
    @Test func everyByteRetainsTheLegacyLowercaseEncoding() {
        let bytes = Array(UInt8.min...UInt8.max)
        let legacy = bytes.map { String(format: "%02x", $0) }.joined()
        #expect(HexEncoding.lowercase(bytes) == legacy)
        #expect(HexEncoding.lowercase(bytes).utf8.count == 512)
        #expect(HexEncoding.lowercase(bytes.reversed()) == bytes.reversed().map { String(format: "%02x", $0) }.joined())
    }

    @Test func emptyLeadingZeroAndSinglePassInputsRetainExactBytes() {
        #expect(HexEncoding.lowercase([UInt8]()) == "")
        #expect(HexEncoding.lowercase([UInt8(0), 1, 15, 16, 128, 255]) == "00010f1080ff")
        let sequence = AnySequence { [UInt8(0), 7, 255].makeIterator() }
        #expect(HexEncoding.lowercase(sequence) == "0007ff")
    }

    @Test func standardSHA256VectorsRetainEveryDigit() {
        #expect(HexEncoding.lowercase(SHA256.hash(data: Data())) ==
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(HexEncoding.lowercase(SHA256.hash(data: Data("abc".utf8))) ==
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

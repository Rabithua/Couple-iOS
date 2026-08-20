import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Couple

struct PhotoLocationExtractorTests {
    @Test("Image metadata coordinates preserve hemispheres")
    func imageMetadataCoordinatesPreserveHemispheres() throws {
        let location = try #require(PhotoLocationExtractor.imageMetadataLocation([
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.868_819_7,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.209_295_5,
                kCGImagePropertyGPSLongitudeRef: "E"
            ] as [CFString: Any]
        ]))

        #expect(location.latitude == -33.868_819_7)
        #expect(location.longitude == 151.209_295_5)
        #expect(location.name == nil)
    }

    @Test("GPS metadata is read from transferred image data")
    func gpsMetadataIsReadFromImageData() throws {
        let data = try makeJPEG(properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 30.240_125,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 120.102_249,
                kCGImagePropertyGPSLongitudeRef: "E"
            ] as [CFString: Any]
        ])

        let location = try #require(PhotoLocationExtractor.imageMetadataLocation(data))
        #expect(abs(location.latitude - 30.240_125) < 0.000_01)
        #expect(abs(location.longitude - 120.102_249) < 0.000_01)
    }

    @Test("Invalid or incomplete image GPS metadata is ignored")
    func invalidMetadataIsIgnored() {
        let missingGPS: [CFString: Any] = [:]
        let incompleteGPS: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 30.0
            ] as [CFString: Any]
        ]
        let invalidGPS: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 100.0,
                kCGImagePropertyGPSLongitude: 120.0
            ] as [CFString: Any]
        ]

        #expect(PhotoLocationExtractor.imageMetadataLocation(missingGPS) == nil)
        #expect(PhotoLocationExtractor.imageMetadataLocation(incompleteGPS) == nil)
        #expect(PhotoLocationExtractor.imageMetadataLocation(invalidGPS) == nil)
    }

    private func makeJPEG(properties: [CFString: Any]) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

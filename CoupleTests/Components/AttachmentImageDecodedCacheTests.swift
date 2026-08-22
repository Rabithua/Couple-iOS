import CoreGraphics
import Testing
import UIKit
@testable import Couple

@MainActor
struct AttachmentImageDecodedCacheTests {
    @Test func fullResolutionRequestUsesAlreadyDecodedVariant() throws {
        let cache = AttachmentImageDecodedCache()
        let thumbnail = try makeImage(pixelDimension: 512)

        cache.insert(
            thumbnail,
            variantKey: "photo|512",
            resourceKey: "photo"
        )

        #expect(cache.image(forVariantKey: "photo|full") == nil)
        #expect(
            cache.bestAvailableImage(
                forResourceKey: "photo",
                targetPixelDimension: nil
            ) === thumbnail
        )
    }

    @Test func finiteRequestUsesSmallestVariantThatMeetsItsTarget() throws {
        let cache = AttachmentImageDecodedCache()
        let small = try makeImage(pixelDimension: 256)
        let medium = try makeImage(pixelDimension: 768)
        let large = try makeImage(pixelDimension: 1_536)

        cache.insert(small, variantKey: "photo|256", resourceKey: "photo")
        cache.insert(medium, variantKey: "photo|768", resourceKey: "photo")
        cache.insert(large, variantKey: "photo|1536", resourceKey: "photo")

        #expect(
            cache.bestAvailableImage(
                forResourceKey: "photo",
                targetPixelDimension: 600
            ) === medium
        )
    }

    @Test func variantsNeverCrossResourceBoundaries() throws {
        let cache = AttachmentImageDecodedCache()
        let firstPhoto = try makeImage(pixelDimension: 512)

        cache.insert(
            firstPhoto,
            variantKey: "first|512",
            resourceKey: "first"
        )

        #expect(
            cache.bestAvailableImage(
                forResourceKey: "second",
                targetPixelDimension: nil
            ) == nil
        )
    }

    private func makeImage(pixelDimension: Int) throws -> UIImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: pixelDimension,
                height: pixelDimension / 2,
                bitsPerComponent: 8,
                bytesPerRow: pixelDimension * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(
            CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension / 2)
        )
        return UIImage(cgImage: try #require(context.makeImage()))
    }
}

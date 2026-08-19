import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Couple

struct AttachmentImageDecoderTests {
    @Test func downsampleCapsPixelSizeAndPreservesAspectRatio() throws {
        let sourceSize = CGSize(width: 2_400, height: 1_200)
        let sourceData = try makeJPEG(size: sourceSize)

        let image = try #require(
            AttachmentImageDecoder.image(
                from: sourceData,
                maximumPixelDimension: 600
            )
        )
        let decodedImage = try #require(image.cgImage)

        #expect(max(decodedImage.width, decodedImage.height) == 600)
        #expect(decodedImage.width == decodedImage.height * 2)
    }

    @Test func namedAssetsDownsampleAcrossColorSpaces() throws {
        let assetNames = [
            "MemoryCeiling",
            "MemoryLake",
            "MemoryMan",
            "MemoryToast",
            "MemoryWoman",
            "MemoryWoman2"
        ]

        for assetName in assetNames {
            let image = try #require(
                AttachmentImageDecoder.image(
                    named: assetName,
                    maximumPixelDimension: 512
                )
            )
            let decodedImage = try #require(image.cgImage)

            #expect(max(decodedImage.width, decodedImage.height) == 512)
        }
    }

    private func makeJPEG(size: CGSize) throws -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let sourceImage = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, sourceImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

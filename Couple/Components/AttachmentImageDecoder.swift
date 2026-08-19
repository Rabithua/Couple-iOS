import ImageIO
import UIKit

enum AttachmentImageDecoder {
    static func image(
        named name: String,
        maximumPixelDimension: Int?
    ) -> UIImage? {
        guard let source = UIImage(named: name) else { return nil }
        guard let maximumPixelDimension,
              maximumPixelDimension > 0,
              let sourceImage = source.cgImage else { return source }

        let sourceMaximumDimension = max(sourceImage.width, sourceImage.height)
        guard sourceMaximumDimension > maximumPixelDimension else { return source }

        let scale = CGFloat(maximumPixelDimension) / CGFloat(sourceMaximumDimension)
        let width = max(Int((CGFloat(sourceImage.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(sourceImage.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let resizedImage = context.makeImage() else { return nil }
        return UIImage(cgImage: resizedImage, scale: 1, orientation: source.imageOrientation)
    }

    static func image(
        from data: Data,
        maximumPixelDimension: Int?
    ) -> UIImage? {
        guard let maximumPixelDimension else { return UIImage(data: data) }
        guard maximumPixelDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        return UIImage(cgImage: image)
    }
}

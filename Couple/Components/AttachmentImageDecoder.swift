import ImageIO
import UIKit

enum AttachmentImageDecoder {
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

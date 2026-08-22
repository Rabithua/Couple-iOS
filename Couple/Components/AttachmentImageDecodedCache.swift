import SwiftUI

@MainActor
final class AttachmentImageDecodedCache {
    static let shared = AttachmentImageDecodedCache()

    private let decodedImages = NSCache<NSString, UIImage>()
    private let liveImages = NSMapTable<NSString, UIImage>(
        keyOptions: .strongMemory,
        valueOptions: .weakMemory
    )
    private var variantKeysByResource: [String: Set<String>] = [:]

    init(countLimit: Int = 40, totalCostLimit: Int = 96 * 1_024 * 1_024) {
        decodedImages.countLimit = countLimit
        decodedImages.totalCostLimit = totalCostLimit
    }

    func image(forVariantKey variantKey: String) -> UIImage? {
        let key = variantKey as NSString
        return decodedImages.object(forKey: key) ?? liveImages.object(forKey: key)
    }

    func bestAvailableImage(
        forResourceKey resourceKey: String,
        targetPixelDimension: Int?
    ) -> UIImage? {
        guard let variantKeys = variantKeysByResource[resourceKey] else { return nil }

        let candidates = variantKeys.compactMap { variantKey -> (UIImage, Int)? in
            guard let image = image(forVariantKey: variantKey) else { return nil }
            return (image, pixelDimension(of: image))
        }
        guard !candidates.isEmpty else {
            variantKeysByResource[resourceKey] = nil
            return nil
        }

        if let targetPixelDimension {
            let largeEnough = candidates.filter { $0.1 >= targetPixelDimension }
            if let closest = largeEnough.min(by: { $0.1 < $1.1 }) {
                return closest.0
            }
        }

        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    func insert(
        _ image: UIImage,
        variantKey: String,
        resourceKey: String
    ) {
        let key = variantKey as NSString
        decodedImages.setObject(image, forKey: key, cost: decodedImageCost(image))
        liveImages.setObject(image, forKey: key)
        variantKeysByResource[resourceKey, default: []].insert(variantKey)
    }

    private func pixelDimension(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return Int(max(image.size.width, image.size.height) * image.scale)
        }
        return max(cgImage.width, cgImage.height)
    }

    private func decodedImageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

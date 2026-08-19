import Foundation
import SwiftUI

actor AttachmentImageCache {
    static let shared = AttachmentImageCache()
    private let memory = NSCache<NSString, NSData>()
    private var inFlight: [String: Task<Data, Error>] = [:]
    private let disk = try? AttachmentFileStore()

    init() {
        memory.countLimit = 100
        memory.totalCostLimit = 64 * 1_024 * 1_024
    }

    func data(for attachment: Attachment, api: APIClient) async throws -> Data? {
        if let cached = memory.object(forKey: attachment.id as NSString) {
            return cached as Data
        }
        guard let path = attachment.url else { return nil }
        if let fileURL = URL(string: path), fileURL.isFileURL {
            return try Data(contentsOf: fileURL)
        }
        if let cached = try await disk?.cachedRemoteData(attachmentId: attachment.id) {
            memory.setObject(cached as NSData, forKey: attachment.id as NSString, cost: cached.count)
            return cached
        }
        if let task = inFlight[attachment.id] {
            return try await task.value
        }

        let task = Task {
            try await api.authorizedData(at: path)
        }
        inFlight[attachment.id] = task

        do {
            let data = try await task.value
            inFlight[attachment.id] = nil
            memory.setObject(
                data as NSData,
                forKey: attachment.id as NSString,
                cost: data.count
            )
            _ = try await disk?.cacheRemoteData(data, attachmentId: attachment.id)
            return data
        } catch {
            inFlight[attachment.id] = nil
            throw error
        }
    }

    func image(
        for attachment: Attachment,
        maximumPixelDimension: Int?,
        api: APIClient
    ) async throws -> UIImage? {
        guard let data = try await data(for: attachment, api: api) else { return nil }
        try Task.checkCancellation()
        return AttachmentImageDecoder.image(
            from: data,
            maximumPixelDimension: maximumPixelDimension
        )
    }
}

@MainActor
struct AttachmentImage: View {
    private static let decodedImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()
    private static let liveImages = NSMapTable<NSString, UIImage>(
        keyOptions: .strongMemory,
        valueOptions: .weakMemory
    )

    let attachment: Attachment
    var contentMode: ContentMode = .fit
    var placeholderColor: Color?
    var maximumDisplayDimension: CGFloat?
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var resolvedCacheKey: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let asset = attachment.demoAssetName {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let displayedImage {
                Image(uiImage: displayedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed, resolvedCacheKey == cacheKey {
                Rectangle()
                    .fill(placeholderColor ?? Color(.systemGray5))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            } else {
                Rectangle()
                    .fill(placeholderColor ?? Color(.systemGray6))
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .clipped()
        .task(id: cacheKey) {
            guard attachment.demoAssetName == nil else { return }

            if let cachedImage = Self.cachedImage(forKey: cacheKey) {
                image = cachedImage
                resolvedCacheKey = cacheKey
                failed = false
                return
            }

            image = nil
            resolvedCacheKey = nil
            failed = false
            do {
                guard let decodedImage = try await AttachmentImageCache.shared.image(
                    for: attachment,
                    maximumPixelDimension: requestedPixelDimension,
                    api: store.api
                ) else {
                    failed = true
                    resolvedCacheKey = cacheKey
                    return
                }
                try Task.checkCancellation()
                Self.decodedImages.setObject(
                    decodedImage,
                    forKey: cacheKey as NSString,
                    cost: decodedImageCost(decodedImage)
                )
                Self.liveImages.setObject(
                    decodedImage,
                    forKey: cacheKey as NSString
                )
                image = decodedImage
                resolvedCacheKey = cacheKey
            } catch is CancellationError {
                return
            } catch {
                failed = true
                resolvedCacheKey = cacheKey
            }
        }
        .accessibilityLabel(attachment.filename)
    }

    private var cacheKey: String {
        let dimension = requestedPixelDimension.map(String.init) ?? "full"
        return "\(attachment.id)|\(attachment.url ?? "")|\(attachment.demoAssetName ?? "")|\(dimension)"
    }

    private var requestedPixelDimension: Int? {
        guard let maximumDisplayDimension,
              maximumDisplayDimension.isFinite,
              maximumDisplayDimension > 0 else { return nil }

        let requiredPixels = Int(ceil(maximumDisplayDimension * displayScale))
        let bucketSize = 256
        return max(
            ((requiredPixels + bucketSize - 1) / bucketSize) * bucketSize,
            bucketSize
        )
    }

    private var displayedImage: UIImage? {
        if resolvedCacheKey == cacheKey, let image {
            return image
        }
        return Self.cachedImage(forKey: cacheKey)
    }

    private static func cachedImage(forKey cacheKey: String) -> UIImage? {
        let key = cacheKey as NSString
        return decodedImages.object(forKey: key) ?? liveImages.object(forKey: key)
    }

    private func decodedImageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

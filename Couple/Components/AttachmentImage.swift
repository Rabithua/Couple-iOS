import Foundation
import SwiftUI
import UIKit

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
}

@MainActor
struct AttachmentImage: View {
    private static let decodedImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

    let attachment: Attachment
    var contentMode: ContentMode = .fit
    @Environment(AppStore.self) private var store
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
                    .fill(Color(.systemGray5))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .clipped()
        .task(id: cacheKey) {
            guard attachment.demoAssetName == nil else { return }

            if let cachedImage = Self.decodedImages.object(forKey: cacheKey as NSString) {
                image = cachedImage
                resolvedCacheKey = cacheKey
                failed = false
                return
            }

            image = nil
            resolvedCacheKey = nil
            failed = false
            do {
                guard let data = try await AttachmentImageCache.shared.data(for: attachment, api: store.api),
                      let decodedImage = UIImage(data: data) else {
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
        "\(attachment.id)|\(attachment.url ?? "")|\(attachment.demoAssetName ?? "")"
    }

    private var displayedImage: UIImage? {
        if resolvedCacheKey == cacheKey, let image {
            return image
        }
        return Self.decodedImages.object(forKey: cacheKey as NSString)
    }

    private func decodedImageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

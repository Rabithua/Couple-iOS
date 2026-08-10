import SwiftUI
import UIKit

actor AttachmentImageCache {
    static let shared = AttachmentImageCache()
    private var memory: [String: Data] = [:]

    func data(for attachment: Attachment, api: APIClient) async throws -> Data? {
        if let cached = memory[attachment.id] { return cached }
        guard let path = attachment.url else { return nil }
        let data = try await api.authorizedData(at: path)
        memory[attachment.id] = data
        return data
    }
}

struct AttachmentImage: View {
    let attachment: Attachment
    var contentMode: ContentMode = .fill
    @Environment(AppStore.self) private var store
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        Group {
            if let asset = attachment.demoAssetName {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
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
        .task(id: attachment.id) {
            guard attachment.demoAssetName == nil else { return }
            do {
                data = try await AttachmentImageCache.shared.data(for: attachment, api: store.api)
            } catch {
                failed = true
            }
        }
        .accessibilityLabel(attachment.filename)
    }
}


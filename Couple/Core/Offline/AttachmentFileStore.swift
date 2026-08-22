import Foundation

struct StagedAttachment: Equatable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
    let width: Int
    let height: Int
    let relativePath: String
}
actor AttachmentFileStore {
    enum StoreError: LocalizedError {
        case applicationSupportUnavailable
        case invalidRelativePath

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable: AppLocalization.string("无法访问应用支持目录")
            case .invalidRelativePath: AppLocalization.string("附件路径无效")
            }
        }
    }

    let pendingDirectory: URL
    let remoteCacheDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw StoreError.applicationSupportUnavailable
            }
            root = applicationSupport.appending(path: "CoupleOfflineV2", directoryHint: .isDirectory)
        }
        pendingDirectory = root.appending(path: "PendingAttachments", directoryHint: .isDirectory)
        remoteCacheDirectory = root.appending(path: "RemoteAttachmentCache", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: remoteCacheDirectory, withIntermediateDirectories: true)
    }

    func stage(_ photo: SelectedPhoto, id: String = UUID().uuidString.lowercased()) throws -> StagedAttachment {
        let safeExtension = URL(fileURLWithPath: photo.filename).pathExtension
        let filename = safeExtension.isEmpty ? id : "\(id).\(safeExtension)"
        let destination = pendingDirectory.appending(path: filename)
        try photo.data.write(to: destination, options: [.atomic])
        return StagedAttachment(
            id: id,
            filename: photo.filename,
            mimeType: photo.mimeType,
            size: photo.data.count,
            width: photo.width,
            height: photo.height,
            relativePath: filename
        )
    }

    func pendingFileURL(relativePath: String) throws -> URL {
        guard !relativePath.contains(".."), !relativePath.contains("/") else {
            throw StoreError.invalidRelativePath
        }
        return pendingDirectory.appending(path: relativePath)
    }

    func pendingData(relativePath: String) throws -> Data {
        try Data(contentsOf: pendingFileURL(relativePath: relativePath))
    }

    func removePending(relativePath: String) throws {
        let url = try pendingFileURL(relativePath: relativePath)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func discardAllPending() throws {
        let files = try fileManager.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files { try fileManager.removeItem(at: file) }
    }

    func discardRemoteCache() throws {
        let files = try fileManager.contentsOfDirectory(
            at: remoteCacheDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files { try fileManager.removeItem(at: file) }
    }

    func cacheRemoteData(_ data: Data, attachmentId: String) throws -> URL {
        let filename = attachmentId.replacingOccurrences(of: "/", with: "_")
        let destination = remoteCacheDirectory.appending(path: filename)
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    func cachedRemoteData(attachmentId: String) throws -> Data? {
        let filename = attachmentId.replacingOccurrences(of: "/", with: "_")
        let url = remoteCacheDirectory.appending(path: filename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}

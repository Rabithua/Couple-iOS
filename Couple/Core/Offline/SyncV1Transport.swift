import Foundation

actor SyncV1Transport: SyncTransport {
    private let api: APIClient
    private let store: OfflineStore

    init(api: APIClient, store: OfflineStore) {
        self.api = api
        self.store = store
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        do {
            let deviceId = try await store.deviceIdentifier()
            var prepared: [PendingOperation] = []
            for operation in operations {
                try Task.checkCancellation()
                prepared.append(try await prepareAttachments(for: operation))
            }
            let response = try await api.sync(
                SyncV1Request(
                    protocolVersion: 1,
                    deviceId: deviceId,
                    cursor: cursor,
                    limit: limit,
                    mutations: try prepared.map {
                        try SyncV1Mutation(operation: $0, deviceId: deviceId)
                    }
                )
            )
            return try response.exchange
        } catch let error as APIError {
            switch error {
            case .server(_, "INVALID_SYNC_CURSOR", _): throw SyncTransportError.invalidCursor
            case .server(_, "OPERATION_ID_REUSED", _): throw SyncTransportError.operationIdReused
            case .server(_, "SYNC_TOMBSTONE_CONFLICT", _): throw SyncTransportError.tombstoneConflict
            case .server(_, "SYNC_DEVICE_REUSED", _): throw SyncTransportError.deviceReused
            case .server(_, "CONFLICT", _): throw SyncTransportError.liveConflict
            case .server(_, "VALIDATION_ERROR", let message):
                throw SyncTransportError.rejected(message)
            case .server(404, _, _):
                try await store.markAttachmentsForReconciliation(
                    parentIds: Set(operations.map(\.entityId))
                )
                throw error
            default: throw error
            }
        }
    }

    func prepareAttachments(for operation: PendingOperation) async throws -> PendingOperation {
        guard !operation.payload.attachmentLocalIds.isEmpty else { return operation }
        let records = try await store.pendingAttachmentRecords(for: operation.entityId)
        let requestedIds = Set(operation.payload.attachmentLocalIds)
        var serverIds: [String] = []

        for record in records where requestedIds.contains(record.localId) {
            if let serverId = record.serverId,
               (record.syncState == AttachmentSyncState.finalized.rawValue
                    || record.syncState == AttachmentSyncState.remote.rawValue) {
                serverIds.append(serverId)
                continue
            }
            guard let width = record.width, let height = record.height else {
                throw SyncTransportError.rejected(AppLocalization.string("待上传照片缺少尺寸信息"))
            }
            let bytes = try await store.pendingAttachment(relativePath: record.relativePath)
            var objectKey = record.uploadObjectKey
            var uploadURL = record.presignedUploadURL.flatMap(URL.init(string:))
            if let existingUploadURL = uploadURL,
               Self.presignedUploadURLIsExpired(existingUploadURL) {
                objectKey = nil
                uploadURL = nil
            }
            if objectKey == nil || uploadURL == nil {
                let prepared = try await prepareUpload(record: record, width: width, height: height)
                objectKey = prepared.objectKey
                uploadURL = prepared.url
            }
            do {
                try await api.upload(bytes, to: uploadURL!, mimeType: record.mimeType)
            } catch APIError.uploadFailed {
                let prepared = try await prepareUpload(record: record, width: width, height: height)
                objectKey = prepared.objectKey
                uploadURL = prepared.url
                try await api.upload(bytes, to: prepared.url, mimeType: record.mimeType)
            }
            let finalized = try await api.finalizeUpload(objectKey: objectKey!)
            try await store.markAttachmentFinalized(localId: record.localId, serverAttachment: finalized)
            serverIds.append(finalized.id)
        }

        guard serverIds.count == requestedIds.count else {
            throw SyncTransportError.rejected(AppLocalization.string("待上传照片记录不完整"))
        }
        var payload = operation.payload
        payload.fields["attachmentIds"] = .strings(serverIds)
        return PendingOperation(
            operationId: operation.operationId,
            entityType: operation.entityType,
            entityId: operation.entityId,
            mutationKind: operation.mutationKind,
            payload: payload,
            changedFieldGroups: operation.changedFieldGroups,
            hlc: operation.hlc,
            retryCount: operation.retryCount,
            createdAt: operation.createdAt
        )
    }

    private func prepareUpload(
        record: LocalPendingAttachment,
        width: Int,
        height: Int
    ) async throws -> (objectKey: String, url: URL) {
        let upload = try await api.requestUpload(
            PresignedUploadRequest(
                filename: record.filename,
                mimeType: record.mimeType,
                size: record.size,
                width: width,
                height: height,
                durationMs: nil
            )
        )
        guard let url = URL(string: upload.presignedUrl) else { throw APIError.invalidResponse }
        try await store.markAttachmentUploadPrepared(
            localId: record.localId,
            serverAttachmentId: upload.attachment.id,
            objectKey: upload.objectKey,
            presignedUploadURL: upload.presignedUrl
        )
        return (upload.objectKey, url)
    }

    static func presignedUploadURLIsExpired(
        _ url: URL,
        at now: Date = .now
    ) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }
        guard let rawDate = query["x-amz-date"],
              let lifetime = TimeInterval(query["x-amz-expires"] ?? "") else {
            return false
        }
        guard rawDate.count == 16, rawDate.hasSuffix("Z") else { return true }
        let characters = Array(rawDate)
        let normalized = "\(String(characters[0..<4]))-"
            + "\(String(characters[4..<6]))-"
            + "\(String(characters[6..<8]))T"
            + "\(String(characters[9..<11])):"
            + "\(String(characters[11..<13])):"
            + "\(String(characters[13..<15]))Z"
        guard let signedAt = ISO8601DateFormatter().date(from: normalized) else { return true }
        return signedAt.addingTimeInterval(lifetime) <= now.addingTimeInterval(30)
    }
}

extension APIClient {
    func sync(_ request: SyncV1Request) async throws -> SyncV1Response {
        try await self.request("/sync", method: .post, body: request)
    }
}

struct SyncV1Request: Encodable, Sendable {
    let protocolVersion: Int
    let deviceId: String
    let cursor: String?
    let limit: Int
    let mutations: [SyncV1Mutation]
}

struct SyncV1Mutation: Encodable, Sendable {
    let operationId: String
    let deviceId: String
    let entityType: String
    let entityId: String
    let kind: String
    let changedGroups: [String]
    let clientHlc: SyncV1ClientHLC
    let data: SyncV1MutationData?

    init(operation: PendingOperation, deviceId: String) throws {
        guard UUID(uuidString: operation.operationId) != nil,
              UUID(uuidString: operation.entityId) != nil,
              UUID(uuidString: deviceId) != nil else {
            throw SyncTransportError.rejected(AppLocalization.string("Sync v1 身份字段必须是 UUID"))
        }
        guard operation.hlc.wallTimeMilliseconds >= 0,
              String(operation.hlc.wallTimeMilliseconds).count <= 16,
              (0...Int64(Int32.max)).contains(operation.hlc.counter) else {
            throw SyncTransportError.rejected(AppLocalization.string("Sync v1 HLC 超出服务端支持范围"))
        }
        try Self.validate(operation)
        operationId = operation.operationId
        self.deviceId = deviceId
        entityType = operation.entityType.rawValue
        entityId = operation.entityId
        kind = operation.mutationKind.rawValue
        changedGroups = operation.changedFieldGroups.sorted()
        clientHlc = SyncV1ClientHLC(operation.hlc)
        data = operation.mutationKind == .delete ? nil : SyncV1MutationData(operation.payload.fields)
    }

    static func validate(_ operation: PendingOperation) throws {
        guard operation.entityType != .attachment else {
            throw SyncTransportError.rejected(AppLocalization.string("attachment 是只读同步实体"))
        }
        let groups = operation.changedFieldGroups
        if operation.mutationKind == .delete {
            guard groups == ["lifecycle"], operation.payload.fields.isEmpty else {
                throw SyncTransportError.rejected(AppLocalization.string("delete 只能提交 lifecycle 且不能携带 data"))
            }
            return
        }
        let definitions = mutableFields(for: operation.entityType)
        if operation.mutationKind == .create || operation.mutationKind == .restore {
            let completeGroups = Set(definitions.keys)
            let legacyMemoryGroups = completeGroups.subtracting(["location"])
            let isCompatibleLegacyMemory = operation.entityType == .memory
                && groups == legacyMemoryGroups
            guard groups == completeGroups || isCompatibleLegacyMemory else {
                throw SyncTransportError.rejected(AppLocalization.string("create/restore 必须提交实体的全部字段组"))
            }
            let requiredFields = Set(
                definitions
                    .filter { groups.contains($0.key) }
                    .values
                    .flatMap { $0 }
            )
            guard requiredFields.isSubset(of: Set(operation.payload.fields.keys)) else {
                throw SyncTransportError.rejected(AppLocalization.string("create/restore 缺少完整 payload"))
            }
            return
        }
        guard !groups.isEmpty else {
            throw SyncTransportError.rejected(AppLocalization.string("update 至少需要一个 changedGroup"))
        }
        for group in groups {
            guard let candidates = definitions[group],
                  !Set(candidates).isDisjoint(with: operation.payload.fields.keys) else {
                throw SyncTransportError.rejected(AppLocalization.string("missingChangedGroupFields",
                    defaultValue: "update 的 \(group) 字段组没有对应字段"
                ))
            }
        }
    }

    private static func mutableFields(for type: SyncEntityType) -> [String: [String]] {
        switch type {
        case .todo: [
            "content": ["title", "note"],
            "schedule": ["dueTime", "reminderEnabled", "reminderOffset", "reminderLocalTime"],
            "visibility": ["visibility"],
            "completion": ["completed"],
        ]
        case .anniversary: [
            "content": ["title"],
            "schedule": ["date", "annual", "reminderEnabled", "reminderOffset", "reminderLocalTime", "reminderInstant"],
            "visibility": ["visibility"],
        ]
        case .calendarEvent: [
            "content": ["title", "description"],
            "schedule": ["allDay", "startTime", "endTime", "timezone", "yearly", "reminderEnabled", "reminderOffset", "reminderLocalTime"],
            "visibility": ["visibility"],
        ]
        case .timeline: [
            "content": ["text", "mood"],
            "schedule": ["eventDate", "sortOrder"],
            "visibility": ["visibility"],
            "attachments": ["attachmentIds"],
        ]
        case .memory: [
            "content": ["content"],
            "associations": ["anniversaryId", "todoId"],
            "location": ["latitude", "longitude", "locationName"],
            "visibility": ["visibility"],
            "attachments": ["attachmentIds"],
        ]
        case .attachment: [:]
        }
    }
}

struct SyncV1ClientHLC: Codable, Equatable, Sendable {
    let wallTimeMs: String
    let counter: Int64
    let deviceId: String?

    init(_ clock: HybridLogicalTimestamp, includeDevice: Bool = false) {
        wallTimeMs = String(clock.wallTimeMilliseconds)
        counter = clock.counter
        deviceId = includeDevice ? clock.deviceId : nil
    }
}

struct SyncV1MutationData: Encodable, Sendable {
    let fields: [String: MutationValue]

    init(_ fields: [String: MutationValue]) {
        self.fields = fields
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (name, value) in fields {
            let key = DynamicCodingKey(name)
            switch value {
            case .string(let item): try container.encode(item, forKey: key)
            case .integer(let item): try container.encode(item, forKey: key)
            case .double(let item): try container.encode(item, forKey: key)
            case .boolean(let item): try container.encode(item, forKey: key)
            case .date(let item): try container.encode(item.apiISOString, forKey: key)
            case .strings(let item): try container.encode(item, forKey: key)
            case .null: try container.encodeNil(forKey: key)
            }
        }
    }
}

struct SyncV1Response: Decodable, Sendable {
    let serverTime: Date
    let authoritativeHlc: SyncV1WireHLC
    let revision: String
    let mode: String
    let acks: [SyncV1Ack]
    let snapshot: [SyncV1Entity]
    let changes: [SyncV1Change]
    let nextCursor: String
    let hasMore: Bool

    var exchange: SyncExchange {
        get throws {
            let snapshotChanges = try snapshot.map {
                try $0.remoteChange(kind: nil, changedGroups: nil, reason: nil)
            }
            let incrementalChanges = try changes.map {
                try $0.entity.remoteChange(
                    kind: $0.kind,
                    changedGroups: Set($0.changedGroups),
                    reason: $0.reason
                )
            }
            return SyncExchange(
                acknowledgedOperationIds: Set(acks.map(\.operationId)),
                page: PullPage(
                    changes: mode == "snapshot" ? snapshotChanges : incrementalChanges,
                    nextCursor: nextCursor,
                    hasMore: hasMore,
                    serverTime: serverTime,
                    authoritativeClock: try authoritativeHlc.timestamp(),
                    mode: mode == "snapshot" ? .snapshot : .incremental,
                    shouldAdoptAuthoritativeClock: acks.contains(where: \.clockAdjusted)
                ),
                requiresAuthoritativeBootstrap: acks.contains {
                    $0.status == "superseded" || !$0.ignoredGroups.isEmpty
                }
            )
        }
    }
}

struct SyncV1Ack: Decodable, Sendable {
    let operationId: String
    let status: String
    let entityType: String
    let entityId: String
    let acceptedGroups: [String]
    let ignoredGroups: [String]
    let revision: String
    let authoritativeHlc: SyncV1WireHLC
    let clockAdjusted: Bool
}

struct SyncV1Change: Decodable, Sendable {
    let sequence: String
    let kind: String
    let changedGroups: [String]
    let reason: String?
    let entity: SyncV1Entity
}

struct SyncV1Entity: Decodable, Sendable {
    let entityType: String
    let entityId: String
    let ownerId: String
    let visibility: String
    let revision: String
    let hlc: SyncV1WireHLC
    let fieldVersions: [String: SyncV1WireHLC]
    let deleted: Bool
    let data: [String: JSONValue]?

    func remoteChange(
        kind: String?,
        changedGroups: Set<String>?,
        reason: String?
    ) throws -> RemoteEntityChange {
        guard let type = SyncEntityType(rawValue: entityType) else {
            throw APIError.decoding(AppLocalization.string("unknownSyncEntityType",
                defaultValue: "未知同步实体类型：\(entityType)"
            ))
        }
        let wireKind: RemoteChangeKind
        if deleted || kind == "delete" {
            wireKind = .delete
        } else if kind == "restore" {
            wireKind = .restore
        } else {
            wireKind = .upsert
        }
        if wireKind != .delete, data == nil {
            throw APIError.decoding(AppLocalization.string(
                "同步实体缺少完整数据：\(entityType)"
            ))
        }
        var fields: [String: MutationValue] = [:]
        for (field, value) in data ?? [:] where field != "attachments" {
            if let mutationValue = try value.mutationValue(
                entityType: type,
                field: field
            ) {
                fields[field] = mutationValue
            }
        }
        if wireKind != .delete, type == .calendarEvent,
           fields["startTime"]?.optionalDateValue == nil {
            throw APIError.decoding(AppLocalization.string(
                "同步日历事件缺少有效的 startTime"
            ))
        }
        let aggregateClock = try hlc.timestamp()
        return RemoteEntityChange(
            entityType: type,
            entityId: entityId,
            ownerId: ownerId,
            visibility: visibility,
            kind: wireKind,
            fields: fields,
            attachments: data?["attachments"]?.remoteAttachments ?? [],
            changedFieldGroups: changedGroups ?? Set(fieldVersions.keys),
            fieldClocks: try fieldVersions.mapValues { try $0.timestamp() },
            tombstone: wireKind == .delete ? aggregateClock : nil,
            updatedAt: fields["updatedAt"]?.optionalDateValue,
            reason: reason
        )
    }
}

struct SyncV1WireHLC: Decodable, Sendable {
    let wallTimeMs: String
    let counter: Int64
    let deviceId: String

    func timestamp() throws -> HybridLogicalTimestamp {
        guard !wallTimeMs.isEmpty,
              wallTimeMs.allSatisfy(\.isNumber),
              let wallTimeMilliseconds = Int64(wallTimeMs),
              (0...Int64(Int32.max)).contains(counter) else {
            throw APIError.decoding(AppLocalization.string("HLC wallTimeMs 或 counter 无效"))
        }
        return HybridLogicalTimestamp(
            wallTimeMilliseconds: wallTimeMilliseconds,
            counter: counter,
            deviceId: deviceId
        )
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

indirect enum JSONValue: Decodable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func mutationValue(
        entityType: SyncEntityType,
        field: String
    ) throws -> MutationValue? {
        if Self.timestampFields[entityType, default: []].contains(field) {
            switch self {
            case .string(let value):
                guard let date = APIISO8601Instant.parse(value) else {
                    throw APIError.decoding(AppLocalization.string(
                        "同步时间字段格式无效：\(entityType.rawValue).\(field)"
                    ))
                }
                return .date(date)
            case .null:
                return .null
            default:
                throw APIError.decoding(AppLocalization.string(
                    "同步时间字段类型无效：\(entityType.rawValue).\(field)"
                ))
            }
        }

        switch self {
        case .string(let value): return .string(value)
        case .integer(let value): return .integer(value)
        case .double(let value): return .double(value)
        case .boolean(let value): return .boolean(value)
        case .array(let values):
            let strings = values.compactMap { value -> String? in
                if case .string(let item) = value { return item }
                return nil
            }
            return strings.count == values.count ? .strings(strings) : nil
        case .object: return nil
        case .null: return .null
        }
    }

    private static let timestampFields: [SyncEntityType: Set<String>] = [
        .todo: ["dueTime", "completedAt", "createdAt", "updatedAt"],
        .anniversary: ["reminderInstant", "createdAt", "updatedAt"],
        .calendarEvent: ["startTime", "endTime", "createdAt", "updatedAt"],
        .memory: ["createdAt", "updatedAt"],
        .timeline: ["createdAt", "updatedAt"],
    ]

    var remoteAttachments: [RemoteAttachmentMetadata]? {
        guard case .array(let values) = self else { return nil }
        return values.compactMap { value in
            guard case .object(let object) = value,
                  let id = object.string("id"),
                  let filename = object.string("filename"),
                  let mimeType = object.string("mimeType"),
                  let size = object.integer("size") else { return nil }
            return RemoteAttachmentMetadata(
                id: id,
                filename: filename,
                mimeType: mimeType,
                size: size,
                width: object.integer("width"),
                height: object.integer("height"),
                durationMilliseconds: object.integer("durationMs"),
                finalized: object.boolean("finalized") ?? true,
                processingStatus: object.string("processingStatus"),
                sortOrder: object.integer("sortOrder") ?? 0,
                url: object.string("url"),
                posterURL: object.string("posterUrl")
            )
        }
    }

}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case .string(let value)? = self[key] else { return nil }
        return value
    }

    func integer(_ key: String) -> Int? {
        switch self[key] {
        case .integer(let value): value
        case .double(let value): Int(value)
        default: nil
        }
    }

    func boolean(_ key: String) -> Bool? {
        guard case .boolean(let value)? = self[key] else { return nil }
        return value
    }
}

private extension MutationValue {
    var optionalDateValue: Date? {
        if case .date(let value) = self { return value }
        return nil
    }
}

import Foundation

protocol SyncV2Transporting: Sendable {
    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncV2Exchange
}

struct SyncV2OperationResult: Equatable, Sendable {
    let operationId: String
    let status: Status
    let sequence: String?
    let replayed: Bool
    let errorCode: String?
    let message: String?

    enum Status: String, Decodable, Sendable {
        case applied
        case rejected
    }
}

struct SyncV2Exchange: Equatable, Sendable {
    let operationResults: [SyncV2OperationResult]
    let page: PullPage
    let snapshotReset: Bool

    init(
        operationResults: [SyncV2OperationResult],
        page: PullPage,
        snapshotReset: Bool = false
    ) {
        self.operationResults = operationResults
        self.page = page
        self.snapshotReset = snapshotReset
    }
}

actor SyncV2Transport: SyncV2Transporting {
    private let api: APIClient
    private let repository: SyncRepositoryV2
    private let attachmentPreparer: SyncV1Transport

    init(api: APIClient, store: OfflineStore, repository: SyncRepositoryV2) {
        self.api = api
        self.repository = repository
        self.attachmentPreparer = SyncV1Transport(api: api, store: store)
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncV2Exchange {
        do {
            let deviceId = try await repository.deviceIdentifier()
            var prepared: [PendingOperation] = []
            for operation in operations {
                try Task.checkCancellation()
                prepared.append(try await attachmentPreparer.prepareAttachments(for: operation))
            }
            let response = try await api.syncV2(
                SyncV2Request(
                    protocolVersion: 2,
                    deviceId: deviceId,
                    cursor: cursor,
                    limit: min(max(limit, 1), 200),
                    operations: try prepared.map(SyncV2Operation.init)
                )
            )
            return try response.exchange
        } catch let error as APIError {
            switch error {
            case .server(_, "SYNC_DEVICE_REUSED", _): throw SyncTransportError.deviceReused
            default: throw error
            }
        }
    }
}

extension APIClient {
    func syncV2(_ request: SyncV2Request) async throws -> SyncV2Response {
        try await self.request("/sync/v2", method: .post, body: request)
    }
}

struct SyncV2Request: Encodable, Sendable {
    let protocolVersion: Int
    let deviceId: String
    let cursor: String?
    let limit: Int
    let operations: [SyncV2Operation]
}

struct SyncV2Operation: Encodable, Sendable {
    let operationId: String
    let entityType: String
    let entityId: String
    let kind: String
    let changedGroups: [String]
    let data: SyncV1MutationData?

    init(operation: PendingOperation) throws {
        guard UUID(uuidString: operation.operationId) != nil,
              UUID(uuidString: operation.entityId) != nil else {
            throw SyncTransportError.rejected(AppLocalization.string("Sync V2 身份字段必须是 UUID"))
        }
        try SyncV1Mutation.validate(operation)
        operationId = operation.operationId
        entityType = operation.entityType.rawValue
        entityId = operation.entityId
        kind = operation.mutationKind.rawValue
        changedGroups = operation.changedFieldGroups.sorted()
        data = operation.mutationKind == .delete ? nil : SyncV1MutationData(operation.payload.fields)
    }
}

private struct SyncV2WireOperationResult: Decodable, Sendable {
    let operationId: String
    let status: SyncV2OperationResult.Status
    let sequence: String?
    let replayed: Bool
    let errorCode: String?
    let message: String?

    var value: SyncV2OperationResult {
        SyncV2OperationResult(
            operationId: operationId,
            status: status,
            sequence: sequence,
            replayed: replayed,
            errorCode: errorCode,
            message: message
        )
    }
}

struct SyncV2Response: Decodable, Sendable {
    let serverTime: Date
    let mode: String
    private let operationResults: [SyncV2WireOperationResult]
    private let changes: [SyncV2WireChange]
    let nextCursor: String
    let hasMore: Bool
    let snapshotReset: Bool?

    var exchange: SyncV2Exchange {
        get throws {
            SyncV2Exchange(
                operationResults: operationResults.map(\.value),
                page: PullPage(
                    changes: try changes.map { try $0.remoteChange(serverTime: serverTime) },
                    nextCursor: nextCursor,
                    hasMore: hasMore,
                    serverTime: serverTime,
                    mode: mode == "snapshot" ? .snapshot : .incremental
                ),
                snapshotReset: snapshotReset ?? false
            )
        }
    }
}

private struct SyncV2WireChange: Decodable, Sendable {
    let sequence: String
    let kind: String
    let changedGroups: [String]
    let reason: String?
    let entity: SyncV2WireEntity

    func remoteChange(serverTime: Date) throws -> RemoteEntityChange {
        try entity.remoteChange(
            sequence: sequence,
            kind: kind,
            changedGroups: Set(changedGroups),
            reason: reason,
            serverTime: serverTime
        )
    }
}

private struct SyncV2WireEntity: Decodable, Sendable {
    let entityType: String
    let entityId: String
    let ownerId: String
    let visibility: String
    let deleted: Bool
    let data: [String: JSONValue]?

    func remoteChange(
        sequence: String,
        kind: String,
        changedGroups: Set<String>,
        reason: String?,
        serverTime: Date
    ) throws -> RemoteEntityChange {
        guard let type = SyncEntityType(rawValue: entityType), type != .attachment else {
            throw APIError.decoding(AppLocalization.string("未知 Sync V2 实体类型：\(entityType)"))
        }
        let isDeleted = deleted || kind == "delete"
        guard isDeleted || data != nil else {
            throw APIError.decoding(AppLocalization.string("Sync V2 实体缺少完整快照：\(entityType)"))
        }
        var fields: [String: MutationValue] = [:]
        for (field, value) in data ?? [:] where field != "attachments" {
            if let converted = try value.mutationValue(entityType: type, field: field) {
                fields[field] = converted
            }
        }
        if !isDeleted, type == .calendarEvent,
           fields["startTime"]?.v2OptionalDate == nil {
            throw APIError.decoding(AppLocalization.string("Sync V2 日历事件缺少 startTime"))
        }
        let remoteClock = HybridLogicalTimestamp(
            wallTimeMilliseconds: serverTime.millisecondsSince1970,
            counter: Int64(sequence) ?? 0,
            deviceId: "server-v2"
        )
        return RemoteEntityChange(
            entityType: type,
            entityId: entityId,
            ownerId: ownerId,
            visibility: visibility,
            kind: isDeleted ? .delete : .upsert,
            fields: fields,
            attachments: data?["attachments"]?.remoteAttachments ?? [],
            changedFieldGroups: changedGroups,
            fieldClocks: Dictionary(uniqueKeysWithValues: changedGroups.map { ($0, remoteClock) }),
            tombstone: isDeleted ? remoteClock : nil,
            updatedAt: fields["updatedAt"]?.v2OptionalDate ?? serverTime,
            reason: reason
        )
    }
}

private extension MutationValue {
    var v2OptionalDate: Date? {
        if case .date(let value) = self { return value }
        return nil
    }
}

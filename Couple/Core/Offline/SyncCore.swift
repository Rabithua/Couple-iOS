import Foundation

enum RemoteChangeKind: String, Codable, Sendable {
    case upsert
    case delete
    case restore
}

enum PullMode: String, Codable, Sendable {
    case snapshot
    case incremental
}

struct RemoteAttachmentMetadata: Equatable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
    let width: Int?
    let height: Int?
    let durationMilliseconds: Int?
    let finalized: Bool
    let processingStatus: String?
    let sortOrder: Int
    let url: String?
    let posterURL: String?
}

struct RemoteEntityChange: Equatable, Sendable {
    let entityType: SyncEntityType
    let entityId: String
    let ownerId: String
    let visibility: String
    let kind: RemoteChangeKind
    let fields: [String: MutationValue]
    let attachments: [RemoteAttachmentMetadata]
    let changedFieldGroups: Set<String>
    let fieldClocks: [String: HybridLogicalTimestamp]
    let tombstone: HybridLogicalTimestamp?
    let updatedAt: Date?
    let reason: String?

    init(
        entityType: SyncEntityType,
        entityId: String,
        ownerId: String,
        visibility: String,
        kind: RemoteChangeKind,
        fields: [String: MutationValue],
        attachments: [RemoteAttachmentMetadata],
        changedFieldGroups: Set<String>,
        fieldClocks: [String: HybridLogicalTimestamp],
        tombstone: HybridLogicalTimestamp?,
        updatedAt: Date?,
        reason: String? = nil
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.ownerId = ownerId
        self.visibility = visibility
        self.kind = kind
        self.fields = fields
        self.attachments = attachments
        self.changedFieldGroups = changedFieldGroups
        self.fieldClocks = fieldClocks
        self.tombstone = tombstone
        self.updatedAt = updatedAt
        self.reason = reason
    }

    var maximumClock: HybridLogicalTimestamp {
        ([tombstone].compactMap { $0 } + Array(fieldClocks.values)).max()
            ?? HybridLogicalTimestamp(
                wallTimeMilliseconds: updatedAt?.millisecondsSince1970 ?? 0,
                counter: 0,
                deviceId: "server"
            )
    }
}

struct SyncExchange: Equatable, Sendable {
    let acknowledgedOperationIds: Set<String>
    let page: PullPage
    let requiresAuthoritativeBootstrap: Bool

    init(
        acknowledgedOperationIds: Set<String>,
        page: PullPage,
        requiresAuthoritativeBootstrap: Bool = false
    ) {
        self.acknowledgedOperationIds = acknowledgedOperationIds
        self.page = page
        self.requiresAuthoritativeBootstrap = requiresAuthoritativeBootstrap
    }
}

struct PullPage: Equatable, Sendable {
    let changes: [RemoteEntityChange]
    let nextCursor: String?
    let hasMore: Bool
    let serverTime: Date?
    let authoritativeClock: HybridLogicalTimestamp?
    let mode: PullMode
    let shouldAdoptAuthoritativeClock: Bool

    init(
        changes: [RemoteEntityChange],
        nextCursor: String?,
        hasMore: Bool,
        serverTime: Date?,
        authoritativeClock: HybridLogicalTimestamp? = nil,
        mode: PullMode = .incremental,
        shouldAdoptAuthoritativeClock: Bool = false
    ) {
        self.changes = changes
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.serverTime = serverTime
        self.authoritativeClock = authoritativeClock
        self.mode = mode
        self.shouldAdoptAuthoritativeClock = shouldAdoptAuthoritativeClock
    }
}

enum SyncTransportError: LocalizedError, Equatable, Sendable {
    case invalidCursor
    case operationIdReused
    case tombstoneConflict
    case deviceReused
    case liveConflict
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidCursor: AppLocalization.string("同步游标失效，需要重新获取快照")
        case .operationIdReused: AppLocalization.string("同步操作标识已被用于不同内容")
        case .tombstoneConflict: AppLocalization.string("服务器已删除该内容，正在获取最终状态")
        case .deviceReused: AppLocalization.string("此安装的同步设备标识与服务器记录冲突")
        case .liveConflict: AppLocalization.string("服务器已有同标识内容，正在获取权威状态")
        case .rejected(let message): message
        }
    }
}

protocol SyncTransport: Sendable {
    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange
}

@MainActor
protocol SyncStore: AnyObject, Sendable {
    func pendingOperations(limit: Int, now: Date) async throws -> [PendingOperation]
    func markSending(operationIds: [String], now: Date) async throws
    func acknowledge(operationIds: [String], now: Date) async throws
    func fail(
        operationIds: [String],
        message: String,
        now: Date,
        retryBaseDelay: TimeInterval
    ) async throws
    func reject(operationIds: [String], message: String, now: Date) async throws
    func cancelSending(operationIds: [String], now: Date) async throws
    func syncCursor() async throws -> String?
    func resetSyncCursor() async throws
    func rotateDeviceIdentifierForReuse() async throws
    func rejectLiveConflict(operationIds: [String], message: String, now: Date) async throws
    func discardTombstonedOperations() async throws -> Int
    func applyRemotePage(_ page: PullPage, now: Date) async throws
}

enum SyncTrigger: String, Sendable {
    case launch
    case login
    case foreground
    case push
    case networkRestored
    case manual
    case retry
}

enum SyncRunResult: Equatable, Sendable {
    case success
    case cancelled
    case failed(String)
}

enum SyncCoordinatorState: Equatable, Sendable {
    case idle
    case syncing(SyncTrigger)
    case waitingForRetry(String)
}

actor SyncCoordinator {
    private let store: any SyncStore
    private let transport: any SyncTransport
    private let batchSize: Int
    private let pageSize: Int
    private let retryBaseDelay: TimeInterval
    private var activeTask: Task<SyncRunResult, Never>?
    private var activeTaskID: UUID?
    private var requestedGeneration: UInt64 = 0
    private(set) var state: SyncCoordinatorState = .idle

    init(
        store: any SyncStore,
        transport: any SyncTransport,
        batchSize: Int = 100,
        pageSize: Int = 200,
        retryBaseDelay: TimeInterval = 2
    ) {
        self.store = store
        self.transport = transport
        self.batchSize = min(max(batchSize, 1), 100)
        self.pageSize = min(max(pageSize, 1), 500)
        self.retryBaseDelay = retryBaseDelay
    }

    func trigger(_ trigger: SyncTrigger) async -> SyncRunResult {
        requestedGeneration &+= 1
        if let activeTask { return await activeTask.value }
        state = .syncing(trigger)
        let taskID = UUID()
        activeTaskID = taskID
        let task = Task { [store, transport, batchSize, pageSize, retryBaseDelay] in
            await self.runUntilQuiescent(
                taskID: taskID,
                store: store,
                transport: transport,
                batchSize: batchSize,
                pageSize: pageSize,
                retryBaseDelay: retryBaseDelay
            )
        }
        activeTask = task
        return await task.value
    }

    func cancel() {
        activeTask?.cancel()
    }

    private func runUntilQuiescent(
        taskID: UUID,
        store: any SyncStore,
        transport: any SyncTransport,
        batchSize: Int,
        pageSize: Int,
        retryBaseDelay: TimeInterval
    ) async -> SyncRunResult {
        var result: SyncRunResult
        repeat {
            let runGeneration = requestedGeneration
            result = await Self.run(
                store: store,
                transport: transport,
                batchSize: batchSize,
                pageSize: pageSize,
                retryBaseDelay: retryBaseDelay
            )
            guard result == .success else { break }
            guard await hasPendingWorkRequested(after: runGeneration, store: store) else { break }
        } while true

        if activeTaskID == taskID {
            activeTask = nil
            activeTaskID = nil
            switch result {
            case .success, .cancelled: state = .idle
            case .failed(let message): state = .waitingForRetry(message)
            }
        }
        return result
    }

    private func hasPendingWorkRequested(
        after runGeneration: UInt64,
        store: any SyncStore
    ) async -> Bool {
        var observedGeneration = runGeneration
        while requestedGeneration != observedGeneration {
            observedGeneration = requestedGeneration
            do {
                let pending = try await store.pendingOperations(limit: 1, now: .now)
                if !pending.isEmpty { return true }
            } catch {
                return true
            }
        }
        return false
    }

    private static func run(
        store: any SyncStore,
        transport: any SyncTransport,
        batchSize: Int,
        pageSize: Int,
        retryBaseDelay: TimeInterval
    ) async -> SyncRunResult {
        var cursor: String?
        var sendingIds: [String] = []
        var restartedSnapshot = false
        var rotatedReusedDevice = false
        var operationLimit = batchSize
        var exchangeCount = 0
        do {
            cursor = try await store.syncCursor()
            while true {
                try Task.checkCancellation()
                exchangeCount += 1
                guard exchangeCount <= 1_000 else {
                    return .failed(AppLocalization.string("同步分页超过安全上限"))
                }

                let operations = try await store.pendingOperations(limit: operationLimit, now: .now)
                sendingIds = operations.map(\.operationId)
                if !sendingIds.isEmpty {
                    try await store.markSending(operationIds: sendingIds, now: .now)
                }

                let exchange: SyncExchange
                do {
                    exchange = try await transport.exchange(
                        cursor: cursor,
                        operations: operations,
                        limit: pageSize
                    )
                } catch SyncTransportError.invalidCursor where !restartedSnapshot {
                    if !sendingIds.isEmpty {
                        try await store.cancelSending(operationIds: sendingIds, now: .now)
                    }
                    sendingIds = []
                    try await store.resetSyncCursor()
                    cursor = nil
                    restartedSnapshot = true
                    continue
                } catch SyncTransportError.deviceReused where !rotatedReusedDevice {
                    if !sendingIds.isEmpty {
                        try await store.cancelSending(operationIds: sendingIds, now: .now)
                    }
                    sendingIds = []
                    try await store.rotateDeviceIdentifierForReuse()
                    cursor = nil
                    restartedSnapshot = false
                    rotatedReusedDevice = true
                    continue
                } catch SyncTransportError.liveConflict where operations.count > 1 {
                    if !sendingIds.isEmpty {
                        try await store.cancelSending(operationIds: sendingIds, now: .now)
                    }
                    sendingIds = []
                    operationLimit = 1
                    continue
                } catch SyncTransportError.liveConflict where operations.count == 1 {
                    try await store.rejectLiveConflict(
                        operationIds: sendingIds,
                        message: SyncTransportError.liveConflict.localizedDescription,
                        now: .now
                    )
                    sendingIds = []
                    try await store.resetSyncCursor()
                    cursor = nil
                    restartedSnapshot = false
                    continue
                } catch SyncTransportError.tombstoneConflict {
                    if !sendingIds.isEmpty {
                        try await store.cancelSending(operationIds: sendingIds, now: .now)
                    }
                    sendingIds = []
                    var recoveryCursor = cursor
                    while true {
                        let recovery = try await transport.exchange(
                            cursor: recoveryCursor,
                            operations: [],
                            limit: pageSize
                        )
                        try await store.applyRemotePage(recovery.page, now: .now)
                        recoveryCursor = recovery.page.nextCursor
                        if !recovery.page.hasMore { break }
                    }
                    let resolvedCount = try await store.discardTombstonedOperations()
                    cursor = recoveryCursor
                    if resolvedCount == 0 {
                        return .failed(AppLocalization.string("服务器已删除该内容，但本地尚未收到对应墓碑"))
                    }
                    continue
                }

                let acknowledged = Array(exchange.acknowledgedOperationIds)
                if !acknowledged.isEmpty {
                    try await store.acknowledge(operationIds: acknowledged, now: .now)
                }
                let unacknowledged = sendingIds.filter {
                    !exchange.acknowledgedOperationIds.contains($0)
                }
                if !unacknowledged.isEmpty {
                    try await store.fail(
                        operationIds: unacknowledged,
                        message: AppLocalization.string("服务端未确认操作"),
                        now: .now,
                        retryBaseDelay: retryBaseDelay
                    )
                    return .failed(AppLocalization.string("服务端未确认操作"))
                }
                sendingIds = []

                try await store.applyRemotePage(exchange.page, now: .now)
                cursor = exchange.page.nextCursor
                if exchange.requiresAuthoritativeBootstrap {
                    try await store.resetSyncCursor()
                    cursor = nil
                    restartedSnapshot = false
                    continue
                }
                if exchange.page.hasMore { continue }
                if operations.isEmpty { return .success }
            }
        } catch is CancellationError {
            if !sendingIds.isEmpty {
                try? await store.cancelSending(operationIds: sendingIds, now: .now)
            }
            return .cancelled
        } catch let error as SyncTransportError where error.isNonRetryable {
            if !sendingIds.isEmpty {
                try? await store.reject(
                    operationIds: sendingIds,
                    message: error.localizedDescription,
                    now: .now
                )
            }
            return .failed(error.localizedDescription)
        } catch {
            if !sendingIds.isEmpty {
                try? await store.fail(
                    operationIds: sendingIds,
                    message: error.localizedDescription,
                    now: .now,
                    retryBaseDelay: retryBaseDelay
                )
            }
            return .failed(error.localizedDescription)
        }
    }
}

private extension SyncTransportError {
    var isNonRetryable: Bool {
        switch self {
        case .operationIdReused, .rejected: true
        case .invalidCursor, .tombstoneConflict, .deviceReused, .liveConflict: false
        }
    }
}

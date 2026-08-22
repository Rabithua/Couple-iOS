import Foundation
import SwiftData

struct SyncV2ApplySummary: Equatable, Sendable {
    let appliedCount: Int
    let rejectedCount: Int
    let changeCount: Int
    let hasPendingOperations: Bool
    let hasBlockedOperations: Bool

    var requiresSnapshotReload: Bool {
        appliedCount > 0 || rejectedCount > 0 || changeCount > 0
    }
}

@ModelActor
actor SyncRepositoryV2 {
    func prepareForSession() throws {
        var changed = false
        for operation in try modelContext.fetch(FetchDescriptor<OutboxEntity>())
        where operation.state == OutboxState.sending.rawValue {
            operation.state = OutboxState.pending.rawValue
            operation.updatedAt = .now
            changed = true
        }
        if changed { try modelContext.save() }
    }

    func deviceIdentifier() throws -> String {
        if let state = try modelContext.fetch(FetchDescriptor<LocalDeviceStateEntity>())
            .first(where: { $0.key == "primary" }) {
            return state.deviceId
        }
        let state = LocalDeviceStateEntity(deviceId: UUID().uuidString.lowercased())
        modelContext.insert(state)
        try modelContext.save()
        return state.deviceId
    }

    func rotateDeviceIdentifier() throws {
        let states = try modelContext.fetch(FetchDescriptor<LocalDeviceStateEntity>())
        let state = states.first(where: { $0.key == "primary" })
            ?? LocalDeviceStateEntity(deviceId: UUID().uuidString.lowercased())
        if states.isEmpty { modelContext.insert(state) }
        state.deviceId = UUID().uuidString.lowercased()
        state.lastWallTimeMilliseconds = 0
        state.counter = 0
        state.serverOffsetMilliseconds = 0
        state.updatedAt = .now
        try resetCursorWithoutSaving()
        try modelContext.save()
    }

    func cursor() throws -> String? {
        try metadata()?.cursor
    }

    func resetCursor() throws {
        try resetCursorWithoutSaving()
        try modelContext.save()
    }

    func pendingOperations(limit: Int, now: Date) throws -> [PendingOperation] {
        let ordered = try modelContext.fetch(FetchDescriptor<OutboxEntity>())
            .sorted(by: Self.ordersBefore)
        var blockedEntities: Set<String> = []
        var result: [PendingOperation] = []
        for operation in ordered {
            let key = Self.entityKey(type: operation.entityType, id: operation.entityId)
            guard !blockedEntities.contains(key) else { continue }
            let state = OutboxState(rawValue: operation.state)
            let ready = state == .pending
                || (state == .failed && (operation.nextRetryAt == nil || operation.nextRetryAt! <= now))
            guard ready else {
                blockedEntities.insert(key)
                continue
            }
            result.append(try Self.mapOperation(operation))
            if result.count == limit { break }
        }
        return result
    }

    func markSending(operationIds: [String], now: Date) throws {
        let ids = Set(operationIds)
        for operation in try modelContext.fetch(FetchDescriptor<OutboxEntity>())
        where ids.contains(operation.operationId) {
            operation.state = OutboxState.sending.rawValue
            operation.updatedAt = now
        }
        try modelContext.save()
    }

    func cancelSending(operationIds: [String], now: Date) throws {
        let ids = Set(operationIds)
        for operation in try modelContext.fetch(FetchDescriptor<OutboxEntity>())
        where ids.contains(operation.operationId)
                && operation.state == OutboxState.sending.rawValue {
            operation.state = OutboxState.pending.rawValue
            operation.updatedAt = now
        }
        try modelContext.save()
    }

    func failSending(
        operationIds: [String],
        message: String,
        now: Date,
        retryBaseDelay: TimeInterval
    ) throws {
        let ids = Set(operationIds)
        for operation in try modelContext.fetch(FetchDescriptor<OutboxEntity>())
        where ids.contains(operation.operationId) {
            operation.retryCount += 1
            let exponent = min(operation.retryCount - 1, 10)
            let base = min(retryBaseDelay * pow(2, Double(exponent)), 300)
            operation.nextRetryAt = now.addingTimeInterval(base * Double.random(in: 0.8...1.2))
            operation.lastError = message
            operation.state = OutboxState.failed.rawValue
            operation.updatedAt = now
        }
        try modelContext.save()
    }

    func queueState(now: Date = .now) throws -> (hasPending: Bool, hasBlocked: Bool, nextRetry: Date?) {
        let operations = try modelContext.fetch(FetchDescriptor<OutboxEntity>())
        let hasBlocked = operations.contains { $0.state == OutboxState.rejected.rawValue }
        let retryable = operations.filter { $0.state != OutboxState.rejected.rawValue }
        let nextRetry = retryable.compactMap { operation -> Date? in
            switch OutboxState(rawValue: operation.state) {
            case .pending, .sending: now
            case .failed: operation.nextRetryAt ?? now
            case .rejected, nil: nil
            }
        }.min()
        return (!retryable.isEmpty, hasBlocked, nextRetry)
    }

    func apply(
        _ exchange: SyncV2Exchange,
        sentOperationIds: [String],
        now: Date
    ) throws -> SyncV2ApplySummary {
        do {
            let expected = Set(sentOperationIds)
            let received = Set(exchange.operationResults.map(\.operationId))
            guard expected == received else {
                throw OfflineStoreError.corruptStoredValue("sync-v2.operationResults")
            }

            let operations = try modelContext.fetch(FetchDescriptor<OutboxEntity>())
            let byId = Dictionary(uniqueKeysWithValues: operations.map { ($0.operationId, $0) })
            var appliedCount = 0
            var rejectedCount = 0
            for result in exchange.operationResults {
                guard let operation = byId[result.operationId] else { continue }
                switch result.status {
                case .applied:
                    modelContext.delete(operation)
                    appliedCount += 1
                case .rejected:
                    operation.state = OutboxState.rejected.rawValue
                    operation.nextRetryAt = nil
                    operation.lastError = result.message
                        ?? result.errorCode
                        ?? AppLocalization.string("同步操作被服务器拒绝")
                    operation.updatedAt = now
                    rejectedCount += 1
                }
            }

            let remaining = try modelContext.fetch(FetchDescriptor<OutboxEntity>())
                .filter { !expected.contains($0.operationId) || $0.state == OutboxState.rejected.rawValue }
            let pendingGroups = Self.pendingGroups(remaining)
            var snapshotSeen: Set<String>?
            if exchange.page.mode == .snapshot {
                snapshotSeen = if exchange.snapshotReset {
                    []
                } else {
                    try metadata()?.snapshotSeenData.map {
                        Set(try Self.decode([String].self, from: $0))
                    } ?? []
                }
            }
            for change in exchange.page.changes {
                snapshotSeen?.insert(Self.entityKey(type: change.entityType.rawValue, id: change.entityId))
                try apply(change, pendingGroups: pendingGroups)
            }
            if exchange.page.mode == .snapshot, !exchange.page.hasMore, let snapshotSeen {
                try hideCleanEntitiesMissingFromSnapshot(seen: snapshotSeen)
            }

            let metadata = try metadata() ?? {
                let value = SyncMetadataEntity(scopeId: OfflineStore.activeScope)
                modelContext.insert(value)
                return value
            }()
            metadata.cursor = exchange.page.nextCursor
            metadata.bootstrapCompleted = exchange.page.mode != .snapshot || !exchange.page.hasMore
            metadata.lastServerTime = exchange.page.serverTime
            metadata.lastSuccessfulSyncAt = now
            metadata.snapshotSeenData = exchange.page.mode == .snapshot && exchange.page.hasMore
                ? try Self.encode(Array(snapshotSeen ?? []).sorted())
                : nil

            try refreshDirtyFlags()
            try modelContext.save()
            let state = try queueState(now: now)
            return SyncV2ApplySummary(
                appliedCount: appliedCount,
                rejectedCount: rejectedCount,
                changeCount: exchange.page.changes.count,
                hasPendingOperations: state.hasPending,
                hasBlockedOperations: state.hasBlocked
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func apply(
        _ change: RemoteEntityChange,
        pendingGroups: [String: Set<String>]
    ) throws {
        let key = Self.entityKey(type: change.entityType.rawValue, id: change.entityId)
        let protected = pendingGroups[key] ?? []
        switch change.entityType {
        case .todo: try applyTodo(change, protected: protected)
        case .anniversary: try applyAnniversary(change, protected: protected)
        case .calendarEvent: try applyCalendarEvent(change, protected: protected)
        case .memory: try applyMemory(change, protected: protected)
        case .timeline: try applyTimeline(change, protected: protected)
        case .attachment: break
        }
    }

    private func applyTodo(_ change: RemoteEntityChange, protected: Set<String>) throws {
        let existing = try find(LocalTodoEntity.self, id: change.entityId)
        if change.kind == .delete {
            if let existing { markDeleted(existing) }
            return
        }
        let timestamp = change.updatedAt ?? .now
        let entity: LocalTodoEntity
        if let existing {
            entity = existing
        } else {
            entity = LocalTodoEntity(
                id: change.entityId.lowercased(),
                coupleId: try activeCoupleId(),
                ownerId: change.ownerId,
                title: change.fields["title"]?.v2String ?? "",
                note: change.fields["note"]?.v2String,
                dueTime: change.fields["dueTime"]?.v2Date,
                visibility: change.visibility,
                completed: change.fields["completed"]?.v2Boolean ?? false,
                completedAt: change.fields["completedAt"]?.v2Date,
                completedBy: change.fields["completedBy"]?.v2String,
                reminderEnabled: change.fields["reminderEnabled"]?.v2Boolean ?? false,
                reminderOffset: change.fields["reminderOffset"]?.v2Integer,
                reminderLocalTime: change.fields["reminderLocalTime"]?.v2String,
                createdAt: change.fields["createdAt"]?.v2Date ?? timestamp,
                updatedAt: timestamp,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
            modelContext.insert(entity)
        }
        guard !protected.contains("lifecycle") else { return }
        entity.isTombstoned = false
        entity.tombstoneClockData = nil
        if !protected.contains("content") {
            if let value = change.fields["title"]?.v2String { entity.title = value }
            if let value = change.fields["note"] { entity.note = value.v2String }
        }
        if !protected.contains("schedule") {
            if let value = change.fields["dueTime"] { entity.dueTime = value.v2Date }
            if let value = change.fields["reminderEnabled"]?.v2Boolean { entity.reminderEnabled = value }
            if let value = change.fields["reminderOffset"] { entity.reminderOffset = value.v2Integer }
            if let value = change.fields["reminderLocalTime"] { entity.reminderLocalTime = value.v2String }
        }
        if !protected.contains("visibility") {
            entity.visibility = change.fields["visibility"]?.v2String ?? change.visibility
        }
        if !protected.contains("completion") {
            if let value = change.fields["completed"]?.v2Boolean { entity.completed = value }
            if let value = change.fields["completedAt"] { entity.completedAt = value.v2Date }
            if let value = change.fields["completedBy"] { entity.completedBy = value.v2String }
        }
        entity.updatedAt = timestamp
    }

    private func applyAnniversary(_ change: RemoteEntityChange, protected: Set<String>) throws {
        let existing = try find(LocalAnniversaryEntity.self, id: change.entityId)
        if change.kind == .delete {
            if let existing { markDeleted(existing) }
            return
        }
        let timestamp = change.updatedAt ?? .now
        let entity: LocalAnniversaryEntity
        if let existing {
            entity = existing
        } else {
            entity = LocalAnniversaryEntity(
                id: change.entityId.lowercased(),
                coupleId: try activeCoupleId(),
                ownerId: change.ownerId,
                title: change.fields["title"]?.v2String ?? "",
                date: change.fields["date"]?.v2String ?? timestamp.dateOnlyString,
                annual: change.fields["annual"]?.v2Boolean ?? true,
                visibility: change.visibility,
                reminderEnabled: change.fields["reminderEnabled"]?.v2Boolean ?? false,
                reminderOffset: change.fields["reminderOffset"]?.v2Integer,
                reminderLocalTime: change.fields["reminderLocalTime"]?.v2String,
                reminderInstant: change.fields["reminderInstant"]?.v2Date,
                createdAt: change.fields["createdAt"]?.v2Date ?? timestamp,
                updatedAt: timestamp,
                nextOccurrence: nil,
                systemKind: change.fields["systemKind"]?.v2String,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
            modelContext.insert(entity)
        }
        guard !protected.contains("lifecycle") else { return }
        entity.isTombstoned = false
        entity.tombstoneClockData = nil
        if !protected.contains("content"), let value = change.fields["title"]?.v2String { entity.title = value }
        if !protected.contains("schedule") {
            if let value = change.fields["date"]?.v2String { entity.date = value }
            if let value = change.fields["annual"]?.v2Boolean { entity.annual = value }
            if let value = change.fields["reminderEnabled"]?.v2Boolean { entity.reminderEnabled = value }
            if let value = change.fields["reminderOffset"] { entity.reminderOffset = value.v2Integer }
            if let value = change.fields["reminderLocalTime"] { entity.reminderLocalTime = value.v2String }
            if let value = change.fields["reminderInstant"] { entity.reminderInstant = value.v2Date }
        }
        if !protected.contains("visibility") {
            entity.visibility = change.fields["visibility"]?.v2String ?? change.visibility
        }
        if let value = change.fields["systemKind"]?.v2String { entity.systemKind = value }
        entity.updatedAt = timestamp
    }

    private func applyCalendarEvent(_ change: RemoteEntityChange, protected: Set<String>) throws {
        let existing = try find(LocalCalendarEventEntity.self, id: change.entityId)
        if change.kind == .delete {
            if let existing { markDeleted(existing) }
            return
        }
        guard let startTime = change.fields["startTime"]?.v2Date else {
            throw OfflineStoreError.corruptStoredValue("sync-v2.calendarEvent.startTime")
        }
        let timestamp = change.updatedAt ?? .now
        let entity: LocalCalendarEventEntity
        if let existing {
            entity = existing
        } else {
            entity = LocalCalendarEventEntity(
                id: change.entityId.lowercased(),
                coupleId: try activeCoupleId(),
                ownerId: change.ownerId,
                title: change.fields["title"]?.v2String ?? "",
                eventDescription: change.fields["description"]?.v2String,
                allDay: change.fields["allDay"]?.v2Boolean ?? false,
                startTime: startTime,
                endTime: change.fields["endTime"]?.v2Date,
                timezone: change.fields["timezone"]?.v2String ?? TimeZone.current.identifier,
                yearly: change.fields["yearly"]?.v2Boolean ?? false,
                visibility: change.visibility,
                reminderEnabled: change.fields["reminderEnabled"]?.v2Boolean ?? false,
                reminderOffset: change.fields["reminderOffset"]?.v2Integer,
                reminderLocalTime: change.fields["reminderLocalTime"]?.v2String,
                createdAt: change.fields["createdAt"]?.v2Date ?? timestamp,
                updatedAt: timestamp,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
            modelContext.insert(entity)
        }
        guard !protected.contains("lifecycle") else { return }
        entity.isTombstoned = false
        entity.tombstoneClockData = nil
        if !protected.contains("content") {
            if let value = change.fields["title"]?.v2String { entity.title = value }
            if let value = change.fields["description"] { entity.eventDescription = value.v2String }
        }
        if !protected.contains("schedule") {
            if let value = change.fields["allDay"]?.v2Boolean { entity.allDay = value }
            entity.startTime = startTime
            if let value = change.fields["endTime"] { entity.endTime = value.v2Date }
            if let value = change.fields["timezone"]?.v2String { entity.timezone = value }
            if let value = change.fields["yearly"]?.v2Boolean { entity.yearly = value }
            if let value = change.fields["reminderEnabled"]?.v2Boolean { entity.reminderEnabled = value }
            if let value = change.fields["reminderOffset"] { entity.reminderOffset = value.v2Integer }
            if let value = change.fields["reminderLocalTime"] { entity.reminderLocalTime = value.v2String }
        }
        if !protected.contains("visibility") {
            entity.visibility = change.fields["visibility"]?.v2String ?? change.visibility
        }
        entity.updatedAt = timestamp
    }

    private func applyMemory(_ change: RemoteEntityChange, protected: Set<String>) throws {
        let existing = try find(LocalMemoryEntity.self, id: change.entityId)
        if change.kind == .delete {
            if let existing { markDeleted(existing) }
            return
        }
        let timestamp = change.updatedAt ?? .now
        let entity: LocalMemoryEntity
        if let existing {
            entity = existing
        } else {
            entity = LocalMemoryEntity(
                id: change.entityId.lowercased(),
                coupleId: try activeCoupleId(),
                ownerId: change.ownerId,
                content: change.fields["content"]?.v2String ?? "",
                visibility: change.visibility,
                anniversaryId: change.fields["anniversaryId"]?.v2String,
                anniversaryTitle: nil,
                todoId: change.fields["todoId"]?.v2String,
                todoTitle: nil,
                createdAt: change.fields["createdAt"]?.v2Date ?? timestamp,
                updatedAt: timestamp,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
            modelContext.insert(entity)
        }
        guard !protected.contains("lifecycle") else { return }
        entity.isTombstoned = false
        entity.tombstoneClockData = nil
        if !protected.contains("content"), let value = change.fields["content"]?.v2String { entity.content = value }
        if !protected.contains("associations") {
            if let value = change.fields["anniversaryId"] { entity.anniversaryId = value.v2String }
            if let value = change.fields["todoId"] { entity.todoId = value.v2String }
        }
        if !protected.contains("visibility") {
            entity.visibility = change.fields["visibility"]?.v2String ?? change.visibility
        }
        if !protected.contains("attachments") {
            try applyAttachments(change.attachments, memoryId: entity.id, timelineId: nil, timestamp: timestamp)
        }
        entity.updatedAt = timestamp
    }

    private func applyTimeline(_ change: RemoteEntityChange, protected: Set<String>) throws {
        let existing = try find(LocalTimelineEntity.self, id: change.entityId)
        if change.kind == .delete {
            if let existing { markDeleted(existing) }
            return
        }
        let timestamp = change.updatedAt ?? .now
        let entity: LocalTimelineEntity
        if let existing {
            entity = existing
        } else {
            entity = LocalTimelineEntity(
                id: change.entityId.lowercased(),
                coupleId: try activeCoupleId(),
                ownerId: change.ownerId,
                eventDate: change.fields["eventDate"]?.v2String ?? timestamp.dateOnlyString,
                text: change.fields["text"]?.v2String ?? "",
                mood: change.fields["mood"]?.v2String,
                visibility: change.visibility,
                sortOrder: change.fields["sortOrder"]?.v2Integer ?? 0,
                createdAt: change.fields["createdAt"]?.v2Date ?? timestamp,
                updatedAt: timestamp,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
            modelContext.insert(entity)
        }
        guard !protected.contains("lifecycle") else { return }
        entity.isTombstoned = false
        entity.tombstoneClockData = nil
        if !protected.contains("content") {
            if let value = change.fields["text"]?.v2String { entity.text = value }
            if let value = change.fields["mood"] { entity.mood = value.v2String }
        }
        if !protected.contains("schedule") {
            if let value = change.fields["eventDate"]?.v2String { entity.eventDate = value }
            if let value = change.fields["sortOrder"]?.v2Integer { entity.sortOrder = value }
        }
        if !protected.contains("visibility") {
            entity.visibility = change.fields["visibility"]?.v2String ?? change.visibility
        }
        if !protected.contains("attachments") {
            try applyAttachments(change.attachments, memoryId: nil, timelineId: entity.id, timestamp: timestamp)
        }
        entity.updatedAt = timestamp
    }

    private func applyAttachments(
        _ remote: [RemoteAttachmentMetadata],
        memoryId: String?,
        timelineId: String?,
        timestamp: Date
    ) throws {
        let all = try modelContext.fetch(FetchDescriptor<LocalAttachmentEntity>())
        let current = all.filter {
            Self.identifiersEqual($0.memoryId, memoryId)
                && Self.identifiersEqual($0.timelineId, timelineId)
        }
        let remoteIds = Set(remote.map { $0.id.lowercased() })
        for local in current where local.serverId != nil
                && !remoteIds.contains((local.serverId ?? local.id).lowercased()) {
            markDeleted(local)
        }
        for attachment in remote {
            let local = current.first {
                Self.identifiersEqual($0.serverId, attachment.id)
                    || Self.identifiersEqual($0.id, attachment.id)
            }
            let entity: LocalAttachmentEntity
            if let local {
                entity = local
            } else {
                entity = LocalAttachmentEntity(
                    id: attachment.id.lowercased(),
                    serverId: attachment.id.lowercased(),
                    memoryId: memoryId,
                    timelineId: timelineId,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    size: attachment.size,
                    width: attachment.width,
                    height: attachment.height,
                    durationMilliseconds: attachment.durationMilliseconds,
                    sortOrder: attachment.sortOrder,
                    localRelativePath: nil,
                    remoteURL: attachment.url,
                    posterURL: attachment.posterURL,
                    syncState: attachment.url == nil
                        ? AttachmentSyncState.finalized.rawValue
                        : AttachmentSyncState.remote.rawValue,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    fieldClocksData: try Self.encode([String: HybridLogicalTimestamp]())
                )
                modelContext.insert(entity)
            }
            entity.serverId = attachment.id.lowercased()
            entity.memoryId = memoryId
            entity.timelineId = timelineId
            entity.filename = attachment.filename
            entity.mimeType = attachment.mimeType
            entity.size = attachment.size
            entity.width = attachment.width
            entity.height = attachment.height
            entity.durationMilliseconds = attachment.durationMilliseconds
            entity.sortOrder = attachment.sortOrder
            entity.remoteURL = attachment.url
            entity.posterURL = attachment.posterURL
            entity.syncState = attachment.url == nil
                ? AttachmentSyncState.finalized.rawValue
                : AttachmentSyncState.remote.rawValue
            entity.isTombstoned = false
            entity.isDirty = false
            entity.updatedAt = timestamp
        }
    }

    private func hideCleanEntitiesMissingFromSnapshot(seen: Set<String>) throws {
        for entity in try modelContext.fetch(FetchDescriptor<LocalTodoEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.entityKey(type: SyncEntityType.todo.rawValue, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalAnniversaryEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.entityKey(type: SyncEntityType.anniversary.rawValue, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalCalendarEventEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.entityKey(type: SyncEntityType.calendarEvent.rawValue, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalMemoryEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.entityKey(type: SyncEntityType.memory.rawValue, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalTimelineEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.entityKey(type: SyncEntityType.timeline.rawValue, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
    }

    private func refreshDirtyFlags() throws {
        let operations = try modelContext.fetch(FetchDescriptor<OutboxEntity>())
        let keys = Set(operations.map { Self.entityKey(type: $0.entityType, id: $0.entityId) })
        for entity in try modelContext.fetch(FetchDescriptor<LocalTodoEntity>()) {
            entity.isDirty = keys.contains(Self.entityKey(type: SyncEntityType.todo.rawValue, id: entity.id))
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalAnniversaryEntity>()) {
            entity.isDirty = keys.contains(Self.entityKey(type: SyncEntityType.anniversary.rawValue, id: entity.id))
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalCalendarEventEntity>()) {
            entity.isDirty = keys.contains(Self.entityKey(type: SyncEntityType.calendarEvent.rawValue, id: entity.id))
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalMemoryEntity>()) {
            entity.isDirty = keys.contains(Self.entityKey(type: SyncEntityType.memory.rawValue, id: entity.id))
        }
        for entity in try modelContext.fetch(FetchDescriptor<LocalTimelineEntity>()) {
            entity.isDirty = keys.contains(Self.entityKey(type: SyncEntityType.timeline.rawValue, id: entity.id))
        }
    }

    private func activeCoupleId() throws -> String {
        guard let session = try modelContext.fetch(FetchDescriptor<LocalSessionEntity>())
            .first(where: { $0.key == "active" }),
              let cached = try? Self.decode(RelationshipStatus.self, from: session.relationshipData),
              let id = cached.couple?.id else {
            return OfflineStore.activeScope
        }
        return id
    }

    private func metadata() throws -> SyncMetadataEntity? {
        try modelContext.fetch(FetchDescriptor<SyncMetadataEntity>())
            .first(where: { $0.scopeId == OfflineStore.activeScope })
    }

    private func resetCursorWithoutSaving() throws {
        let metadata = try metadata() ?? {
            let value = SyncMetadataEntity(scopeId: OfflineStore.activeScope)
            modelContext.insert(value)
            return value
        }()
        metadata.cursor = nil
        metadata.bootstrapCompleted = false
        metadata.snapshotSeenData = nil
    }

    private func find<T>(_ type: T.Type, id: String) throws -> T?
    where T: PersistentModel, T: LocalSyncEntity {
        try modelContext.fetch(FetchDescriptor<T>())
            .first { Self.identifiersEqual($0.id, id) }
    }

    private func markDeleted<T: LocalSyncLifecycle>(_ entity: T) {
        entity.isTombstoned = true
        entity.isDirty = false
        entity.tombstoneClockData = nil
    }

    private func markVisibilityRevoked<T: LocalSyncLifecycle>(_ entity: T) {
        entity.isTombstoned = true
        entity.tombstoneClockData = nil
    }

    private static func pendingGroups(_ operations: [OutboxEntity]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for operation in operations {
            let key = entityKey(type: operation.entityType, id: operation.entityId)
            result[key, default: []].formUnion(operation.changedFieldGroups)
        }
        return result
    }

    private static func ordersBefore(_ left: OutboxEntity, _ right: OutboxEntity) -> Bool {
        if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
        let leftPriority = mutationPriority(left.mutationKind)
        let rightPriority = mutationPriority(right.mutationKind)
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        return left.operationId < right.operationId
    }

    private static func mutationPriority(_ value: String) -> Int {
        switch MutationKind(rawValue: value) {
        case .create, .restore: 0
        case .update: 1
        case .delete: 2
        case nil: 3
        }
    }

    private static func mapOperation(_ entity: OutboxEntity) throws -> PendingOperation {
        guard let type = SyncEntityType(rawValue: entity.entityType),
              let kind = MutationKind(rawValue: entity.mutationKind) else {
            throw OfflineStoreError.corruptStoredValue("sync-v2.outbox")
        }
        return PendingOperation(
            operationId: entity.operationId,
            entityType: type,
            entityId: entity.entityId,
            mutationKind: kind,
            payload: try decode(LocalMutationPayload.self, from: entity.payloadData),
            changedFieldGroups: Set(entity.changedFieldGroups),
            hlc: try decode(HybridLogicalTimestamp.self, from: entity.hlcData),
            retryCount: entity.retryCount,
            createdAt: entity.createdAt
        )
    }

    private static func entityKey(type: String, id: String) -> String {
        "\(type):\(id.lowercased())"
    }

    private static func identifiersEqual(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case let (.some(left), .some(right)): left.caseInsensitiveCompare(right) == .orderedSame
        case (nil, nil): true
        default: false
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }
}

private extension MutationValue {
    var v2String: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var v2Date: Date? {
        if case .date(let value) = self { return value }
        return nil
    }

    var v2Integer: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var v2Boolean: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }
}

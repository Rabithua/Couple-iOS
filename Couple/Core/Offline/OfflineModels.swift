import Foundation
import SwiftData

enum SyncEntityType: String, Codable, CaseIterable, Sendable {
    case todo
    case anniversary
    case calendarEvent
    case memory = "note"
    case timeline = "timelineEntry"
    case attachment
}

enum MutationKind: String, Codable, Sendable {
    case create
    case update
    case delete
    case restore
}

enum OutboxState: String, Codable, Sendable {
    case pending
    case sending
    case failed
    case rejected
}

enum AttachmentSyncState: String, Codable, Sendable {
    case pending
    case uploading
    case finalized
    case failed
    case remote
}

enum MutationValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case date(Date)
    case strings([String])
    case null
}

struct LocalMutationPayload: Codable, Equatable, Sendable {
    var fields: [String: MutationValue]
    var attachmentLocalIds: [String]

    init(fields: [String: MutationValue], attachmentLocalIds: [String] = []) {
        self.fields = fields
        self.attachmentLocalIds = attachmentLocalIds
    }
}

struct PendingOperation: Identifiable, Equatable, Sendable {
    let operationId: String
    let entityType: SyncEntityType
    let entityId: String
    let mutationKind: MutationKind
    let payload: LocalMutationPayload
    let changedFieldGroups: Set<String>
    let hlc: HybridLogicalTimestamp
    let retryCount: Int
    let createdAt: Date

    var id: String { operationId }
}

@Model
final class LocalTodoEntity {
    @Attribute(.unique) var id: String
    var coupleId: String
    var ownerId: String
    var title: String
    var note: String?
    var dueTime: Date?
    var visibility: String
    var completed: Bool
    var completedAt: Date?
    var completedBy: String?
    var reminderOffset: Int?
    var createdAt: Date
    var updatedAt: Date
    var fieldClocksData: Data
    var tombstoneClockData: Data?
    var isTombstoned: Bool
    var isDirty: Bool

    init(
        id: String,
        coupleId: String,
        ownerId: String,
        title: String,
        note: String?,
        dueTime: Date?,
        visibility: String,
        completed: Bool,
        completedAt: Date?,
        completedBy: String?,
        reminderOffset: Int?,
        createdAt: Date,
        updatedAt: Date,
        fieldClocksData: Data,
        tombstoneClockData: Data? = nil,
        isTombstoned: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.coupleId = coupleId
        self.ownerId = ownerId
        self.title = title
        self.note = note
        self.dueTime = dueTime
        self.visibility = visibility
        self.completed = completed
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.reminderOffset = reminderOffset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fieldClocksData = fieldClocksData
        self.tombstoneClockData = tombstoneClockData
        self.isTombstoned = isTombstoned
        self.isDirty = isDirty
    }
}

@Model
final class LocalAnniversaryEntity {
    @Attribute(.unique) var id: String
    var coupleId: String
    var ownerId: String
    var title: String
    var date: String
    var annual: Bool
    var visibility: String
    var reminderOffset: Int?
    var reminderInstant: Date?
    var createdAt: Date
    var updatedAt: Date
    var nextOccurrence: String?
    var fieldClocksData: Data
    var tombstoneClockData: Data?
    var isTombstoned: Bool
    var isDirty: Bool

    init(
        id: String,
        coupleId: String,
        ownerId: String,
        title: String,
        date: String,
        annual: Bool,
        visibility: String,
        reminderOffset: Int?,
        reminderInstant: Date?,
        createdAt: Date,
        updatedAt: Date,
        nextOccurrence: String?,
        fieldClocksData: Data,
        tombstoneClockData: Data? = nil,
        isTombstoned: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.coupleId = coupleId
        self.ownerId = ownerId
        self.title = title
        self.date = date
        self.annual = annual
        self.visibility = visibility
        self.reminderOffset = reminderOffset
        self.reminderInstant = reminderInstant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextOccurrence = nextOccurrence
        self.fieldClocksData = fieldClocksData
        self.tombstoneClockData = tombstoneClockData
        self.isTombstoned = isTombstoned
        self.isDirty = isDirty
    }
}

@Model
final class LocalCalendarEventEntity {
    @Attribute(.unique) var id: String
    var coupleId: String
    var ownerId: String
    var title: String
    var eventDescription: String?
    var allDay: Bool
    var startTime: Date
    var endTime: Date?
    var timezone: String
    var yearly: Bool
    var visibility: String
    var reminderOffset: Int?
    var createdAt: Date
    var updatedAt: Date
    var fieldClocksData: Data
    var tombstoneClockData: Data?
    var isTombstoned: Bool
    var isDirty: Bool

    init(
        id: String,
        coupleId: String,
        ownerId: String,
        title: String,
        eventDescription: String?,
        allDay: Bool,
        startTime: Date,
        endTime: Date?,
        timezone: String,
        yearly: Bool,
        visibility: String,
        reminderOffset: Int?,
        createdAt: Date,
        updatedAt: Date,
        fieldClocksData: Data,
        tombstoneClockData: Data? = nil,
        isTombstoned: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.coupleId = coupleId
        self.ownerId = ownerId
        self.title = title
        self.eventDescription = eventDescription
        self.allDay = allDay
        self.startTime = startTime
        self.endTime = endTime
        self.timezone = timezone
        self.yearly = yearly
        self.visibility = visibility
        self.reminderOffset = reminderOffset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fieldClocksData = fieldClocksData
        self.tombstoneClockData = tombstoneClockData
        self.isTombstoned = isTombstoned
        self.isDirty = isDirty
    }
}

@Model
final class LocalMemoryEntity {
    @Attribute(.unique) var id: String
    var coupleId: String
    var ownerId: String
    var content: String
    var visibility: String
    var anniversaryId: String?
    var anniversaryTitle: String?
    var todoId: String?
    var todoTitle: String?
    var createdAt: Date
    var updatedAt: Date
    var fieldClocksData: Data
    var tombstoneClockData: Data?
    var isTombstoned: Bool
    var isDirty: Bool

    init(
        id: String,
        coupleId: String,
        ownerId: String,
        content: String,
        visibility: String,
        anniversaryId: String?,
        anniversaryTitle: String?,
        todoId: String?,
        todoTitle: String?,
        createdAt: Date,
        updatedAt: Date,
        fieldClocksData: Data,
        tombstoneClockData: Data? = nil,
        isTombstoned: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.coupleId = coupleId
        self.ownerId = ownerId
        self.content = content
        self.visibility = visibility
        self.anniversaryId = anniversaryId
        self.anniversaryTitle = anniversaryTitle
        self.todoId = todoId
        self.todoTitle = todoTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fieldClocksData = fieldClocksData
        self.tombstoneClockData = tombstoneClockData
        self.isTombstoned = isTombstoned
        self.isDirty = isDirty
    }
}

@Model
final class LocalTimelineEntity {
    @Attribute(.unique) var id: String
    var coupleId: String
    var ownerId: String
    var eventDate: String
    var text: String
    var mood: String?
    var visibility: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var fieldClocksData: Data
    var tombstoneClockData: Data?
    var isTombstoned: Bool
    var isDirty: Bool

    init(
        id: String,
        coupleId: String,
        ownerId: String,
        eventDate: String,
        text: String,
        mood: String?,
        visibility: String,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date,
        fieldClocksData: Data,
        tombstoneClockData: Data? = nil,
        isTombstoned: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.coupleId = coupleId
        self.ownerId = ownerId
        self.eventDate = eventDate
        self.text = text
        self.mood = mood
        self.visibility = visibility
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fieldClocksData = fieldClocksData
        self.tombstoneClockData = tombstoneClockData
        self.isTombstoned = isTombstoned
        self.isDirty = isDirty
    }
}

@Model
final class LocalAttachmentEntity {
    @Attribute(.unique) var id: String
    var serverId: String?
    var memoryId: String?
    var timelineId: String?
    var filename: String
    var mimeType: String
    var size: Int
    var width: Int?
    var height: Int?
    var durationMilliseconds: Int?
    var sortOrder: Int
    var localRelativePath: String?
    var remoteURL: String?
    var posterURL: String?
    var uploadObjectKey: String?
    var presignedUploadURL: String?
    var syncState: String
    var createdAt: Date
    var updatedAt: Date
    var fieldClocksData: Data
    var tombstoneClockData: Data?
    var isTombstoned: Bool
    var isDirty: Bool

    init(
        id: String,
        serverId: String? = nil,
        memoryId: String? = nil,
        timelineId: String? = nil,
        filename: String,
        mimeType: String,
        size: Int,
        width: Int?,
        height: Int?,
        durationMilliseconds: Int?,
        sortOrder: Int,
        localRelativePath: String?,
        remoteURL: String?,
        posterURL: String?,
        uploadObjectKey: String? = nil,
        presignedUploadURL: String? = nil,
        syncState: String,
        createdAt: Date,
        updatedAt: Date,
        fieldClocksData: Data,
        tombstoneClockData: Data? = nil,
        isTombstoned: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.memoryId = memoryId
        self.timelineId = timelineId
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.width = width
        self.height = height
        self.durationMilliseconds = durationMilliseconds
        self.sortOrder = sortOrder
        self.localRelativePath = localRelativePath
        self.remoteURL = remoteURL
        self.posterURL = posterURL
        self.uploadObjectKey = uploadObjectKey
        self.presignedUploadURL = presignedUploadURL
        self.syncState = syncState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fieldClocksData = fieldClocksData
        self.tombstoneClockData = tombstoneClockData
        self.isTombstoned = isTombstoned
        self.isDirty = isDirty
    }
}

@Model
final class OutboxEntity {
    @Attribute(.unique) var operationId: String
    var entityType: String
    var entityId: String
    var mutationKind: String
    var payloadData: Data
    var changedFieldGroups: [String]
    var hlcData: Data
    var state: String
    var retryCount: Int
    var nextRetryAt: Date?
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        operationId: String,
        entityType: String,
        entityId: String,
        mutationKind: String,
        payloadData: Data,
        changedFieldGroups: [String],
        hlcData: Data,
        state: String = OutboxState.pending.rawValue,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastError: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.operationId = operationId
        self.entityType = entityType
        self.entityId = entityId
        self.mutationKind = mutationKind
        self.payloadData = payloadData
        self.changedFieldGroups = changedFieldGroups
        self.hlcData = hlcData
        self.state = state
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SyncMetadataEntity {
    @Attribute(.unique) var scopeId: String
    var cursor: String?
    var bootstrapCompleted: Bool
    var lastServerTime: Date?
    var lastSuccessfulSyncAt: Date?
    var snapshotSeenData: Data?

    init(
        scopeId: String,
        cursor: String? = nil,
        bootstrapCompleted: Bool = false,
        lastServerTime: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        snapshotSeenData: Data? = nil
    ) {
        self.scopeId = scopeId
        self.cursor = cursor
        self.bootstrapCompleted = bootstrapCompleted
        self.lastServerTime = lastServerTime
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.snapshotSeenData = snapshotSeenData
    }
}

@Model
final class LocalDeviceStateEntity {
    @Attribute(.unique) var key: String
    var deviceId: String
    var lastWallTimeMilliseconds: Int64
    var counter: Int64
    var serverOffsetMilliseconds: Int64
    var updatedAt: Date

    init(
        key: String = "primary",
        deviceId: String,
        lastWallTimeMilliseconds: Int64 = 0,
        counter: Int64 = 0,
        serverOffsetMilliseconds: Int64 = 0,
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.deviceId = deviceId
        self.lastWallTimeMilliseconds = lastWallTimeMilliseconds
        self.counter = counter
        self.serverOffsetMilliseconds = serverOffsetMilliseconds
        self.updatedAt = updatedAt
    }
}

@Model
final class LocalSessionEntity {
    @Attribute(.unique) var key: String
    var userData: Data
    var relationshipData: Data
    var homeData: Data?
    var updatedAt: Date

    init(
        key: String = "active",
        userData: Data,
        relationshipData: Data,
        homeData: Data?,
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.userData = userData
        self.relationshipData = relationshipData
        self.homeData = homeData
        self.updatedAt = updatedAt
    }
}

enum OfflineSchema {
    static let models: [any PersistentModel.Type] = [
        LocalTodoEntity.self,
        LocalAnniversaryEntity.self,
        LocalCalendarEventEntity.self,
        LocalMemoryEntity.self,
        LocalTimelineEntity.self,
        LocalAttachmentEntity.self,
        OutboxEntity.self,
        SyncMetadataEntity.self,
        LocalDeviceStateEntity.self,
        LocalSessionEntity.self,
    ]
}

protocol LocalSyncLifecycle: AnyObject {
    var fieldClocksData: Data { get set }
    var tombstoneClockData: Data? { get set }
    var isTombstoned: Bool { get set }
    var isDirty: Bool { get set }
}

extension LocalTodoEntity: LocalSyncLifecycle {}
extension LocalAnniversaryEntity: LocalSyncLifecycle {}
extension LocalCalendarEventEntity: LocalSyncLifecycle {}
extension LocalMemoryEntity: LocalSyncLifecycle {}
extension LocalTimelineEntity: LocalSyncLifecycle {}
extension LocalAttachmentEntity: LocalSyncLifecycle {}

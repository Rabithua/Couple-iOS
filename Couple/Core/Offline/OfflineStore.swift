import Foundation
import SwiftData

struct OfflineSnapshot: Sendable {
    let notes: [Note]
    let todos: [Todo]
    let anniversaries: [Anniversary]
    let canonicalCalendarEvents: [CalendarEvent]
    let timelineEntries: [TimelineEntry]
}

struct CachedSession: Sendable {
    let user: User
    let relationship: RelationshipStatus
    let home: HomeData?
}

enum OfflineStoreError: LocalizedError {
    case missingEntity(SyncEntityType, String)
    case corruptStoredValue(String)

    var errorDescription: String? {
        switch self {
        case .missingEntity(let type, let id): "本地找不到 \(type.rawValue)：\(id)"
        case .corruptStoredValue(let name): "本地数据损坏：\(name)"
        }
    }
}

@MainActor
final class OfflineStore: SyncStore {
    static let activeScope = "active-couple"

    let container: ModelContainer
    let attachmentFiles: AttachmentFileStore
    private let context: ModelContext

    init(container: ModelContainer, attachmentFiles: AttachmentFileStore) throws {
        self.container = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.attachmentFiles = attachmentFiles
        try recoverInterruptedOperations()
        try repairCaseVariantDuplicates()
    }

    static func makeLive() throws -> OfflineStore {
        let schema = Schema(OfflineSchema.models)
        let configuration = ModelConfiguration(
            "CoupleOffline",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return try OfflineStore(container: container, attachmentFiles: AttachmentFileStore())
    }

    static func makeInMemory(attachmentRoot: URL) throws -> OfflineStore {
        let schema = Schema(OfflineSchema.models)
        let configuration = ModelConfiguration(
            "CoupleOfflineTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return try OfflineStore(
            container: container,
            attachmentFiles: AttachmentFileStore(rootDirectory: attachmentRoot)
        )
    }

    static func makePersistent(storeURL: URL, attachmentRoot: URL) throws -> OfflineStore {
        let schema = Schema(OfflineSchema.models)
        let configuration = ModelConfiguration(
            "CoupleOfflineTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return try OfflineStore(
            container: container,
            attachmentFiles: AttachmentFileStore(rootDirectory: attachmentRoot)
        )
    }

    func loadSnapshot() async throws -> OfflineSnapshot {
        let localAttachments = try context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            .filter { !$0.isTombstoned }
        var attachmentsByMemory: [String: [Attachment]] = [:]
        for local in localAttachments {
            guard let memoryId = local.memoryId else { continue }
            let attachment = try await mapAttachment(local)
            attachmentsByMemory[memoryId.lowercased(), default: []].append(attachment)
        }
        for key in attachmentsByMemory.keys {
            attachmentsByMemory[key]?.sort { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }

        let notes = Self.deduplicatedEntities(
            try context.fetch(FetchDescriptor<LocalMemoryEntity>())
                .filter { !$0.isTombstoned }
        )
            .sorted { $0.createdAt > $1.createdAt }
            .map { local in
                var associations: [NoteAssociation] = []
                if let id = local.anniversaryId {
                    associations.append(.init(type: .anniversary, id: id, title: local.anniversaryTitle))
                }
                if let id = local.todoId {
                    associations.append(.init(type: .todo, id: id, title: local.todoTitle))
                }
                return Note(
                    id: local.id,
                    coupleId: local.coupleId,
                    ownerId: local.ownerId,
                    content: local.content,
                    visibility: Visibility(rawValue: local.visibility) ?? .shared,
                    anniversaryId: local.anniversaryId,
                    todoId: local.todoId,
                    createdAt: local.createdAt,
                    updatedAt: local.updatedAt,
                    associations: associations,
                    attachments: attachmentsByMemory[local.id.lowercased()] ?? []
                )
            }

        let todos = Self.deduplicatedEntities(
            try context.fetch(FetchDescriptor<LocalTodoEntity>())
                .filter { !$0.isTombstoned }
        )
            .sorted { $0.createdAt > $1.createdAt }
            .map(mapTodo)
        let anniversaries = Self.deduplicatedEntities(
            try context.fetch(FetchDescriptor<LocalAnniversaryEntity>())
                .filter { !$0.isTombstoned }
        )
            .sorted { $0.date < $1.date }
            .map(mapAnniversary)
        let calendar = Self.deduplicatedEntities(
            try context.fetch(FetchDescriptor<LocalCalendarEventEntity>())
                .filter { !$0.isTombstoned }
        )
            .sorted { $0.startTime < $1.startTime }
            .map(mapCalendarEvent)
        let timeline = Self.deduplicatedEntities(
            try context.fetch(FetchDescriptor<LocalTimelineEntity>())
                .filter { !$0.isTombstoned }
        )
            .sorted {
                if $0.eventDate == $1.eventDate { return $0.sortOrder < $1.sortOrder }
                return $0.eventDate > $1.eventDate
            }
            .map(mapTimeline)

        return OfflineSnapshot(
            notes: notes,
            todos: todos,
            anniversaries: anniversaries,
            canonicalCalendarEvents: calendar,
            timelineEntries: timeline
        )
    }

    func saveSession(user: User, relationship: RelationshipStatus, home: HomeData?) throws {
        let userData = try Self.encode(user)
        let relationshipData = try Self.encode(relationship)
        let homeData = try home.map(Self.encode)
        if let entity = try context.fetch(FetchDescriptor<LocalSessionEntity>()).first(where: { $0.key == "active" }) {
            entity.userData = userData
            entity.relationshipData = relationshipData
            entity.homeData = homeData
            entity.updatedAt = .now
        } else {
            context.insert(
                LocalSessionEntity(
                    userData: userData,
                    relationshipData: relationshipData,
                    homeData: homeData
                )
            )
        }
        try context.save()
    }

    func cachedSession() throws -> CachedSession? {
        guard let entity = try context.fetch(FetchDescriptor<LocalSessionEntity>())
            .first(where: { $0.key == "active" }) else { return nil }
        return CachedSession(
            user: try Self.decode(User.self, from: entity.userData),
            relationship: try Self.decode(RelationshipStatus.self, from: entity.relationshipData),
            home: try entity.homeData.map { try Self.decode(HomeData.self, from: $0) }
        )
    }

    func updateCachedHome(_ home: HomeData) throws {
        guard let entity = try context.fetch(FetchDescriptor<LocalSessionEntity>())
            .first(where: { $0.key == "active" }) else { return }
        entity.homeData = try Self.encode(home)
        entity.updatedAt = .now
        try context.save()
    }

    func bootstrap(
        notes: [Note],
        todos: [Todo],
        anniversaries: [Anniversary],
        calendarEvents: [CalendarEvent],
        timelineEntries: [TimelineEntry] = [],
        cursor: String? = nil,
        serverTime: Date? = nil
    ) throws {
        if let serverTime { try calibrateClock(serverTime: serverTime, receivedAt: .now) }
        for todo in todos { try mergeRemote(todo) }
        for anniversary in anniversaries { try mergeRemote(anniversary) }
        for event in calendarEvents where event.occurrenceId == nil && event.recurrenceSourceId == nil {
            try mergeRemote(event)
        }
        for note in notes { try mergeRemote(note) }
        for entry in timelineEntries { try mergeRemote(entry) }
        try updateMetadata(cursor: cursor, bootstrapCompleted: true, serverTime: serverTime)
        try context.save()
    }

    func createTodo(
        coupleId: String,
        ownerId: String,
        title: String,
        dueDate: Date?,
        visibility: Visibility,
        now: Date = .now
    ) throws -> Todo {
        let id = UUID().uuidString.lowercased()
        let hlc = try nextHLC(at: now)
        let clocks = try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility", "completion"], hlc: hlc))
        let entity = LocalTodoEntity(
            id: id,
            coupleId: coupleId,
            ownerId: ownerId,
            title: title,
            note: nil,
            dueTime: dueDate,
            visibility: visibility.rawValue,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: dueDate == nil ? nil : 60,
            createdAt: now,
            updatedAt: now,
            fieldClocksData: clocks,
            isDirty: true
        )
        context.insert(entity)
        try enqueue(
            entityType: .todo,
            entityId: id,
            kind: .create,
            payload: todoPayload(entity),
            changedGroups: ["content", "schedule", "visibility", "completion"],
            hlc: hlc,
            now: now
        )
        try context.save()
        return mapTodo(entity)
    }

    func editTodoTitle(id: String, title: String, now: Date = .now) throws {
        guard let entity = try todoEntity(id: id) else { throw OfflineStoreError.missingEntity(.todo, id) }
        guard !entity.isTombstoned else { return }
        let hlc = try nextHLC(at: now)
        entity.title = title
        entity.updatedAt = now
        entity.isDirty = true
        try setClock(hlc, group: "content", on: entity)
        try enqueue(
            entityType: .todo,
            entityId: id,
            kind: .update,
            payload: .init(fields: ["title": .string(title)]),
            changedGroups: ["content"],
            hlc: hlc,
            now: now
        )
        try context.save()
    }

    func editTodo(
        id: String,
        title: String,
        dueDate: Date?,
        visibility: Visibility,
        now: Date = .now
    ) throws {
        guard let entity = try todoEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.todo, id)
        }
        guard !entity.isTombstoned else { return }
        let hlc = try nextHLC(at: now)
        let groups: Set<String> = ["content", "schedule", "visibility"]
        entity.title = title
        entity.dueTime = dueDate
        entity.reminderOffset = dueDate == nil ? nil : (entity.reminderOffset ?? 60)
        entity.visibility = visibility.rawValue
        entity.updatedAt = now
        entity.isDirty = true
        try setClock(hlc, groups: groups, on: entity)
        try enqueue(
            entityType: .todo,
            entityId: id,
            kind: .update,
            payload: .init(fields: [
                "title": .string(title),
                "dueTime": dueDate.map(MutationValue.date) ?? .null,
                "reminderOffset": entity.reminderOffset.map(MutationValue.integer) ?? .null,
                "visibility": .string(visibility.rawValue),
            ]),
            changedGroups: groups,
            hlc: hlc,
            now: now
        )
        try context.save()
    }

    func toggleTodo(id: String, completedBy: String?, now: Date = .now) throws -> Todo {
        guard let entity = try todoEntity(id: id) else { throw OfflineStoreError.missingEntity(.todo, id) }
        guard !entity.isTombstoned else { throw OfflineStoreError.missingEntity(.todo, id) }
        return try setTodoCompletion(
            id: id,
            completed: !entity.completed,
            completedBy: completedBy,
            now: now
        )
    }

    func setTodoCompletion(
        id: String,
        completed: Bool,
        completedBy: String?,
        now: Date = .now
    ) throws -> Todo {
        guard let entity = try todoEntity(id: id) else { throw OfflineStoreError.missingEntity(.todo, id) }
        guard !entity.isTombstoned else { throw OfflineStoreError.missingEntity(.todo, id) }
        guard entity.completed != completed else { return mapTodo(entity) }
        let hlc = try nextHLC(at: now)
        entity.completed = completed
        entity.completedAt = completed ? now : nil
        entity.completedBy = completed ? completedBy : nil
        entity.updatedAt = now
        entity.isDirty = true
        try setClock(hlc, group: "completion", on: entity)
        try enqueue(
            entityType: .todo,
            entityId: id,
            kind: .update,
            payload: .init(fields: [
                "completed": .boolean(entity.completed),
            ]),
            changedGroups: ["completion"],
            hlc: hlc,
            now: now
        )
        try context.save()
        return mapTodo(entity)
    }

    func deleteTodo(id: String, now: Date = .now) throws {
        guard let entity = try todoEntity(id: id) else { throw OfflineStoreError.missingEntity(.todo, id) }
        try delete(entity, entityType: .todo, now: now)
    }

    func restoreTodo(id: String, now: Date = .now) throws -> Todo {
        guard let entity = try todoEntity(id: id), entity.isTombstoned else {
            throw OfflineStoreError.missingEntity(.todo, id)
        }
        let hlc = try nextHLC(at: now)
        if let tombstoneData = entity.tombstoneClockData {
            let tombstone = try Self.decode(HybridLogicalTimestamp.self, from: tombstoneData)
            guard tombstone < hlc else {
                throw OfflineStoreError.corruptStoredValue("restore HLC")
            }
        }
        entity.isTombstoned = false
        entity.isDirty = true
        entity.tombstoneClockData = nil
        entity.updatedAt = now
        entity.fieldClocksData = try Self.encode(Self.clocks(
            groups: ["content", "schedule", "visibility", "completion"],
            hlc: hlc
        ))
        try enqueue(
            entityType: .todo,
            entityId: id,
            kind: .restore,
            payload: todoPayload(entity),
            changedGroups: ["content", "schedule", "visibility", "completion"],
            hlc: hlc,
            now: now
        )
        try context.save()
        return mapTodo(entity)
    }

    func createAnniversary(
        coupleId: String,
        ownerId: String,
        title: String,
        date: Date,
        annual: Bool,
        visibility: Visibility,
        now: Date = .now
    ) throws -> Anniversary {
        let id = UUID().uuidString.lowercased()
        let hlc = try nextHLC(at: now)
        let entity = LocalAnniversaryEntity(
            id: id,
            coupleId: coupleId,
            ownerId: ownerId,
            title: title,
            date: date.dateOnlyString,
            annual: annual,
            visibility: visibility.rawValue,
            reminderOffset: 1_440,
            reminderInstant: nil,
            createdAt: now,
            updatedAt: now,
            nextOccurrence: nil,
            fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility"], hlc: hlc)),
            isDirty: true
        )
        context.insert(entity)
        try enqueue(
            entityType: .anniversary,
            entityId: id,
            kind: .create,
            payload: anniversaryPayload(entity),
            changedGroups: ["content", "schedule", "visibility"],
            hlc: hlc,
            now: now
        )
        try context.save()
        return mapAnniversary(entity)
    }

    func editAnniversary(
        id: String,
        title: String,
        date: Date,
        annual: Bool,
        visibility: Visibility,
        now: Date = .now
    ) throws {
        guard let entity = try anniversaryEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.anniversary, id)
        }
        guard !entity.isTombstoned else { return }
        let hlc = try nextHLC(at: now)
        let groups: Set<String> = ["content", "schedule", "visibility"]
        entity.title = title
        entity.date = date.dateOnlyString
        entity.annual = annual
        entity.visibility = visibility.rawValue
        entity.updatedAt = now
        entity.isDirty = true
        try setClock(hlc, groups: groups, on: entity)
        try enqueue(
            entityType: .anniversary,
            entityId: id,
            kind: .update,
            payload: .init(fields: [
                "title": .string(title),
                "date": .string(entity.date),
                "annual": .boolean(annual),
                "visibility": .string(visibility.rawValue),
            ]),
            changedGroups: groups,
            hlc: hlc,
            now: now
        )
        try context.save()
    }

    func deleteAnniversary(id: String, now: Date = .now) throws {
        guard let entity = try anniversaryEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.anniversary, id)
        }
        try delete(entity, entityType: .anniversary, now: now)
    }

    func createCalendarEvent(
        coupleId: String,
        ownerId: String,
        title: String,
        start: Date,
        end: Date?,
        allDay: Bool,
        yearly: Bool = false,
        visibility: Visibility = .shared,
        now: Date = .now
    ) throws -> CalendarEvent {
        let id = UUID().uuidString.lowercased()
        let hlc = try nextHLC(at: now)
        let entity = LocalCalendarEventEntity(
            id: id,
            coupleId: coupleId,
            ownerId: ownerId,
            title: title,
            eventDescription: nil,
            allDay: allDay,
            startTime: start,
            endTime: end,
            timezone: TimeZone.current.identifier,
            yearly: yearly,
            visibility: visibility.rawValue,
            reminderOffset: 60,
            createdAt: now,
            updatedAt: now,
            fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility"], hlc: hlc)),
            isDirty: true
        )
        context.insert(entity)
        try enqueue(
            entityType: .calendarEvent,
            entityId: id,
            kind: .create,
            payload: calendarPayload(entity),
            changedGroups: ["content", "schedule", "visibility"],
            hlc: hlc,
            now: now
        )
        try context.save()
        return mapCalendarEvent(entity)
    }

    func editCalendarEvent(
        id: String,
        title: String,
        start: Date,
        end: Date?,
        allDay: Bool,
        now: Date = .now
    ) throws {
        guard let entity = try calendarEventEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.calendarEvent, id)
        }
        guard !entity.isTombstoned else { return }
        let hlc = try nextHLC(at: now)
        let groups: Set<String> = ["content", "schedule"]
        entity.title = title
        entity.startTime = start
        entity.endTime = end
        entity.allDay = allDay
        entity.updatedAt = now
        entity.isDirty = true
        try setClock(hlc, groups: groups, on: entity)
        try enqueue(
            entityType: .calendarEvent,
            entityId: id,
            kind: .update,
            payload: .init(fields: [
                "title": .string(title),
                "allDay": .boolean(allDay),
                "startTime": .date(start),
                "endTime": end.map(MutationValue.date) ?? .null,
            ]),
            changedGroups: groups,
            hlc: hlc,
            now: now
        )
        try context.save()
    }

    func deleteCalendarEvent(id: String, now: Date = .now) throws {
        guard let entity = try calendarEventEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.calendarEvent, id)
        }
        try delete(entity, entityType: .calendarEvent, now: now)
    }

    func createMemory(
        coupleId: String,
        ownerId: String,
        content: String,
        photos: [SelectedPhoto],
        anniversaryId: String?,
        anniversaryTitle: String?,
        todoId: String?,
        todoTitle: String?,
        visibility: Visibility,
        now: Date = .now
    ) async throws -> Note {
        let memoryId = UUID().uuidString.lowercased()
        var staged: [StagedAttachment] = []
        do {
            for photo in photos { staged.append(try await attachmentFiles.stage(photo)) }
            let hlc = try nextHLC(at: now)
            let entity = LocalMemoryEntity(
                id: memoryId,
                coupleId: coupleId,
                ownerId: ownerId,
                content: content,
                visibility: visibility.rawValue,
                anniversaryId: anniversaryId,
                anniversaryTitle: anniversaryTitle,
                todoId: todoId,
                todoTitle: todoTitle,
                createdAt: now,
                updatedAt: now,
                fieldClocksData: try Self.encode(Self.clocks(
                    groups: ["content", "associations", "visibility", "attachments"],
                    hlc: hlc
                )),
                isDirty: true
            )
            context.insert(entity)
            for (index, file) in staged.enumerated() {
                context.insert(
                    LocalAttachmentEntity(
                        id: file.id,
                        memoryId: memoryId,
                        filename: file.filename,
                        mimeType: file.mimeType,
                        size: file.size,
                        width: file.width,
                        height: file.height,
                        durationMilliseconds: nil,
                        sortOrder: index,
                        localRelativePath: file.relativePath,
                        remoteURL: nil,
                        posterURL: nil,
                        syncState: AttachmentSyncState.pending.rawValue,
                        createdAt: now,
                        updatedAt: now,
                        fieldClocksData: try Self.encode(Self.clocks(groups: ["metadata", "location"], hlc: hlc)),
                        isDirty: true
                    )
                )
            }
            let payload = LocalMutationPayload(
                fields: memoryPayload(entity).fields,
                attachmentLocalIds: staged.map(\.id)
            )
            try enqueue(
                entityType: .memory,
                entityId: memoryId,
                kind: .create,
                payload: payload,
                changedGroups: ["content", "associations", "visibility", "attachments"],
                hlc: hlc,
                now: now
            )
            try context.save()
            return try await loadSnapshot().notes.first(where: {
                Self.identifiersEqual($0.id, memoryId)
            })
                ?? { throw OfflineStoreError.missingEntity(.memory, memoryId) }()
        } catch {
            for file in staged { try? await attachmentFiles.removePending(relativePath: file.relativePath) }
            context.rollback()
            throw error
        }
    }

    func editMemory(
        id: String,
        content: String,
        anniversaryId: String?,
        anniversaryTitle: String?,
        todoId: String?,
        todoTitle: String?,
        visibility: Visibility,
        now: Date = .now
    ) throws {
        guard let entity = try memoryEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.memory, id)
        }
        guard !entity.isTombstoned else { return }
        let hlc = try nextHLC(at: now)
        let groups: Set<String> = ["content", "associations", "visibility"]
        entity.content = content
        entity.anniversaryId = anniversaryId
        entity.anniversaryTitle = anniversaryTitle
        entity.todoId = todoId
        entity.todoTitle = todoTitle
        entity.visibility = visibility.rawValue
        entity.updatedAt = now
        entity.isDirty = true
        try setClock(hlc, groups: groups, on: entity)
        try enqueue(
            entityType: .memory,
            entityId: id,
            kind: .update,
            payload: .init(fields: [
                "content": .string(content),
                "anniversaryId": anniversaryId.map(MutationValue.string) ?? .null,
                "todoId": todoId.map(MutationValue.string) ?? .null,
                "visibility": .string(visibility.rawValue),
            ]),
            changedGroups: groups,
            hlc: hlc,
            now: now
        )
        try context.save()
    }

    func deleteMemory(id: String, now: Date = .now) throws {
        guard let entity = try memoryEntity(id: id) else {
            throw OfflineStoreError.missingEntity(.memory, id)
        }
        try delete(entity, entityType: .memory, now: now)
    }

    func createTimelineEntry(
        coupleId: String,
        ownerId: String,
        eventDate: Date,
        text: String,
        mood: String?,
        sortOrder: Int,
        photos: [SelectedPhoto],
        visibility: Visibility,
        now: Date = .now
    ) async throws -> TimelineEntry {
        let entryId = UUID().uuidString.lowercased()
        var staged: [StagedAttachment] = []
        do {
            for photo in photos { staged.append(try await attachmentFiles.stage(photo)) }
            let hlc = try nextHLC(at: now)
            let entity = LocalTimelineEntity(
                id: entryId,
                coupleId: coupleId,
                ownerId: ownerId,
                eventDate: eventDate.dateOnlyString,
                text: text,
                mood: mood,
                visibility: visibility.rawValue,
                sortOrder: sortOrder,
                createdAt: now,
                updatedAt: now,
                fieldClocksData: try Self.encode(Self.clocks(
                    groups: ["content", "schedule", "visibility", "attachments"],
                    hlc: hlc
                )),
                isDirty: true
            )
            context.insert(entity)
            for (index, file) in staged.enumerated() {
                context.insert(
                    LocalAttachmentEntity(
                        id: file.id,
                        timelineId: entryId,
                        filename: file.filename,
                        mimeType: file.mimeType,
                        size: file.size,
                        width: file.width,
                        height: file.height,
                        durationMilliseconds: nil,
                        sortOrder: index,
                        localRelativePath: file.relativePath,
                        remoteURL: nil,
                        posterURL: nil,
                        syncState: AttachmentSyncState.pending.rawValue,
                        createdAt: now,
                        updatedAt: now,
                        fieldClocksData: try Self.encode(Self.clocks(groups: ["metadata"], hlc: hlc)),
                        isDirty: true
                    )
                )
            }
            var payload = timelinePayload(entity)
            payload.attachmentLocalIds = staged.map(\.id)
            try enqueue(
                entityType: .timeline,
                entityId: entryId,
                kind: .create,
                payload: payload,
                changedGroups: ["content", "schedule", "visibility", "attachments"],
                hlc: hlc,
                now: now
            )
            try context.save()
            return mapTimeline(entity)
        } catch {
            for file in staged { try? await attachmentFiles.removePending(relativePath: file.relativePath) }
            context.rollback()
            throw error
        }
    }

    func pendingAttachment(relativePath: String) async throws -> Data {
        try await attachmentFiles.pendingData(relativePath: relativePath)
    }

    func pendingAttachmentRecords(for parentId: String) throws -> [LocalPendingAttachment] {
        try context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            .filter {
                (Self.identifiersEqual($0.memoryId, parentId)
                    || Self.identifiersEqual($0.timelineId, parentId))
                    && !$0.isTombstoned
                    && $0.localRelativePath != nil
            }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                LocalPendingAttachment(
                    localId: $0.id,
                    serverId: $0.serverId,
                    filename: $0.filename,
                    mimeType: $0.mimeType,
                    size: $0.size,
                    width: $0.width,
                    height: $0.height,
                    syncState: $0.syncState,
                    uploadObjectKey: $0.uploadObjectKey,
                    presignedUploadURL: $0.presignedUploadURL,
                    relativePath: $0.localRelativePath ?? ""
                )
            }
    }

    func markAttachmentUploadPrepared(
        localId: String,
        serverAttachmentId: String,
        objectKey: String,
        presignedUploadURL: String
    ) throws {
        guard let entity = try attachmentEntity(id: localId) else { return }
        entity.serverId = serverAttachmentId
        entity.uploadObjectKey = objectKey
        entity.presignedUploadURL = presignedUploadURL
        entity.syncState = AttachmentSyncState.uploading.rawValue
        entity.updatedAt = .now
        try context.save()
    }

    func markAttachmentFinalized(localId: String, serverAttachment: Attachment) throws {
        guard let entity = try attachmentEntity(id: localId) else { return }
        entity.serverId = serverAttachment.id
        entity.remoteURL = serverAttachment.url
        entity.posterURL = serverAttachment.posterUrl
        entity.syncState = AttachmentSyncState.finalized.rawValue
        entity.isDirty = false
        entity.updatedAt = .now
        try context.save()
    }

    func markAttachmentsForReconciliation(parentIds: Set<String>) throws {
        guard !parentIds.isEmpty else { return }
        for attachment in try context.fetch(FetchDescriptor<LocalAttachmentEntity>()) {
            guard let parentId = attachment.memoryId ?? attachment.timelineId,
                  parentIds.contains(parentId),
                  attachment.syncState == AttachmentSyncState.finalized.rawValue else { continue }
            attachment.syncState = AttachmentSyncState.uploading.rawValue
            attachment.isDirty = true
            attachment.updatedAt = .now
        }
        try context.save()
    }

    func unsyncedCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<OutboxEntity>())
    }

    func clearSynchronizedLocalDataForSignOut() throws {
        guard try unsyncedCount() == 0 else {
            throw OfflineStoreError.corruptStoredValue("sign out with pending outbox")
        }
        try deleteAll(LocalTodoEntity.self)
        try deleteAll(LocalAnniversaryEntity.self)
        try deleteAll(LocalCalendarEventEntity.self)
        try deleteAll(LocalMemoryEntity.self)
        try deleteAll(LocalTimelineEntity.self)
        try deleteAll(LocalAttachmentEntity.self)
        try deleteAll(SyncMetadataEntity.self)
        try deleteAll(LocalSessionEntity.self)
        try context.save()
    }

    func discardPendingMutationsAndLocalData() async throws {
        try await attachmentFiles.discardAllPending()
        try deleteAll(LocalTodoEntity.self)
        try deleteAll(LocalAnniversaryEntity.self)
        try deleteAll(LocalCalendarEventEntity.self)
        try deleteAll(LocalMemoryEntity.self)
        try deleteAll(LocalTimelineEntity.self)
        try deleteAll(LocalAttachmentEntity.self)
        try deleteAll(OutboxEntity.self)
        try deleteAll(SyncMetadataEntity.self)
        try deleteAll(LocalSessionEntity.self)
        try context.save()
    }

    func pendingOperations(limit: Int, now: Date) async throws -> [PendingOperation] {
        let entities = try context.fetch(FetchDescriptor<OutboxEntity>())
            .filter {
                ($0.state == OutboxState.pending.rawValue || $0.state == OutboxState.failed.rawValue)
                    && ($0.nextRetryAt == nil || $0.nextRetryAt! <= now)
            }
            .sorted { $0.createdAt < $1.createdAt }
        return try entities.prefix(limit).map(mapOperation)
    }

    func markSending(operationIds: [String], now: Date) async throws {
        let ids = Set(operationIds)
        for entity in try context.fetch(FetchDescriptor<OutboxEntity>()) where ids.contains(entity.operationId) {
            entity.state = OutboxState.sending.rawValue
            entity.updatedAt = now
        }
        try context.save()
    }

    func acknowledge(operationIds: [String], now: Date) async throws {
        let ids = Set(operationIds)
        let acknowledged = try context.fetch(FetchDescriptor<OutboxEntity>())
            .filter { ids.contains($0.operationId) }
        let affected = acknowledged.map { ($0.entityType, $0.entityId) }
        for entity in acknowledged { context.delete(entity) }
        for (type, id) in affected where try !hasPendingOperation(entityType: type, entityId: id) {
            try markEntityClean(entityType: type, entityId: id)
        }
        try context.save()
    }

    func fail(
        operationIds: [String],
        message: String,
        now: Date,
        retryBaseDelay: TimeInterval
    ) async throws {
        let ids = Set(operationIds)
        for entity in try context.fetch(FetchDescriptor<OutboxEntity>()) where ids.contains(entity.operationId) {
            entity.retryCount += 1
            let exponent = min(entity.retryCount - 1, 10)
            let delay = min(retryBaseDelay * pow(2, Double(exponent)), 3_600)
            entity.nextRetryAt = now.addingTimeInterval(delay)
            entity.lastError = message
            entity.state = OutboxState.failed.rawValue
            entity.updatedAt = now
        }
        try context.save()
    }

    func reject(operationIds: [String], message: String, now: Date) async throws {
        let ids = Set(operationIds)
        for entity in try context.fetch(FetchDescriptor<OutboxEntity>()) where ids.contains(entity.operationId) {
            entity.nextRetryAt = nil
            entity.lastError = message
            entity.state = OutboxState.rejected.rawValue
            entity.updatedAt = now
        }
        try context.save()
    }

    func cancelSending(operationIds: [String], now: Date) async throws {
        let ids = Set(operationIds)
        for entity in try context.fetch(FetchDescriptor<OutboxEntity>()) where ids.contains(entity.operationId) {
            entity.state = OutboxState.pending.rawValue
            entity.updatedAt = now
        }
        try context.save()
    }

    func syncCursor() async throws -> String? {
        try metadata()?.cursor
    }

    func resetSyncCursor() async throws {
        try updateMetadata(
            cursor: nil,
            bootstrapCompleted: false,
            serverTime: nil
        )
        let metadata = try metadata()
        metadata?.snapshotSeenData = nil
        try context.save()
    }

    func rotateDeviceIdentifierForReuse() async throws {
        let state = try deviceState()
        state.deviceId = UUID().uuidString.lowercased()
        state.lastWallTimeMilliseconds = 0
        state.counter = 0
        state.serverOffsetMilliseconds = 0
        state.updatedAt = .now
        try await resetSyncCursor()
    }

    func rejectLiveConflict(operationIds: [String], message: String, now: Date) async throws {
        let ids = Set(operationIds)
        let emptyClocks = try Self.encode([String: HybridLogicalTimestamp]())
        for operation in try context.fetch(FetchDescriptor<OutboxEntity>()) where ids.contains(operation.operationId) {
            operation.nextRetryAt = nil
            operation.lastError = message
            operation.state = OutboxState.rejected.rawValue
            operation.updatedAt = now
            try resetFieldClocks(
                entityType: SyncEntityType(rawValue: operation.entityType),
                entityId: operation.entityId,
                to: emptyClocks
            )
        }
        try context.save()
    }

    func discardTombstonedOperations() async throws -> Int {
        let operations = try context.fetch(FetchDescriptor<OutboxEntity>())
        var affected: [(String, String)] = []
        var resolvedCount = 0
        for operation in operations {
            guard try isLocallyTombstoned(
                entityType: operation.entityType,
                entityId: operation.entityId
            ) else { continue }
            if operation.mutationKind == MutationKind.restore.rawValue {
                operation.state = OutboxState.rejected.rawValue
                operation.nextRetryAt = nil
                operation.lastError = "恢复操作的 HLC 不晚于服务器墓碑"
                operation.updatedAt = .now
                resolvedCount += 1
                continue
            }
            guard operation.mutationKind == MutationKind.create.rawValue
                    || operation.mutationKind == MutationKind.update.rawValue else { continue }
            affected.append((operation.entityType, operation.entityId))
            context.delete(operation)
            resolvedCount += 1
        }
        for (type, id) in affected where try !hasPendingOperation(entityType: type, entityId: id) {
            try markEntityClean(entityType: type, entityId: id)
        }
        try context.save()
        return resolvedCount
    }

    func deviceIdentifier() throws -> String {
        let state = try deviceState()
        if context.hasChanges { try context.save() }
        return state.deviceId
    }

    func applyRemotePage(_ page: PullPage, now: Date) async throws {
        if let serverTime = page.serverTime { try calibrateClock(serverTime: serverTime, receivedAt: now) }
        if let authoritativeClock = page.authoritativeClock {
            if page.shouldAdoptAuthoritativeClock {
                try adoptAuthoritativeClock(authoritativeClock, at: now)
            } else {
                try observeClock(authoritativeClock, at: now)
            }
        }
        var snapshotSeen: Set<String>?
        if page.mode == .snapshot {
            snapshotSeen = try metadata()?.snapshotSeenData.map {
                Set(try Self.decode([String].self, from: $0))
            } ?? []
            for change in page.changes {
                snapshotSeen?.insert(Self.snapshotKey(type: change.entityType, id: change.entityId))
            }
        }
        for change in page.changes {
            try observeClock(change.maximumClock, at: now)
            try apply(change)
        }
        if page.mode == .snapshot, !page.hasMore, let snapshotSeen {
            try hideCleanEntitiesMissingFromSnapshot(seen: snapshotSeen)
        }
        try updateMetadata(
            cursor: page.nextCursor,
            bootstrapCompleted: true,
            serverTime: page.serverTime,
            successfulSyncAt: now
        )
        if let metadata = try metadata() {
            metadata.snapshotSeenData = page.mode == .snapshot && page.hasMore
                ? try Self.encode(Array(snapshotSeen ?? []).sorted())
                : nil
        }
        try context.save()
        try await cleanReadyAttachmentFiles()
    }

    private func apply(_ change: RemoteEntityChange) throws {
        if change.kind == .delete, change.reason == "visibilityRevoked" {
            try applyVisibilityRevocation(change)
            return
        }
        switch change.entityType {
        case .todo: try applyTodo(change)
        case .anniversary: try applyAnniversary(change)
        case .calendarEvent: try applyCalendarEvent(change)
        case .memory: try applyMemory(change)
        case .timeline: try applyTimeline(change)
        case .attachment: try applyStandaloneAttachment(change)
        }
    }

    private func applyTodo(_ change: RemoteEntityChange) throws {
        let entity: LocalTodoEntity
        if let existing = try todoEntity(id: change.entityId) {
            entity = existing
        } else {
            entity = LocalTodoEntity(
                id: change.entityId.lowercased(),
                coupleId: try activeCoupleId(),
                ownerId: change.ownerId,
                title: change.fields["title"]?.optionalString ?? "",
                note: change.fields["note"]?.optionalString,
                dueTime: change.fields["dueTime"]?.optionalDate,
                visibility: change.visibility,
                completed: change.fields["completed"]?.optionalBoolean ?? false,
                completedAt: change.fields["completedAt"]?.optionalDate,
                completedBy: change.fields["completedBy"]?.optionalString,
                reminderOffset: change.fields["reminderOffset"]?.optionalInteger,
                createdAt: change.updatedAt ?? change.maximumClock.date,
                updatedAt: change.updatedAt ?? change.maximumClock.date,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
            context.insert(entity)
        }
        if change.kind == .delete {
            entity.isTombstoned = true
            entity.isDirty = false
            entity.tombstoneClockData = try Self.encode(change.tombstone ?? change.maximumClock)
            return
        }
        if entity.isTombstoned, entity.tombstoneClockData == nil {
            entity.isTombstoned = false
        }
        guard !entity.isTombstoned else { return }
        var clocks = try clocks(from: entity.fieldClocksData)
        for group in change.changedFieldGroups {
            guard let remoteClock = change.fieldClocks[group] else { continue }
            let localClock = clocks[group]
            guard localClock == nil || localClock! <= remoteClock else { continue }
            switch group {
            case "content":
                if let title = change.fields["title"]?.optionalString { entity.title = title }
                if let note = change.fields["note"] { entity.note = note.optionalString }
            case "schedule":
                if let due = change.fields["dueTime"] { entity.dueTime = due.optionalDate }
                if let reminder = change.fields["reminderOffset"] { entity.reminderOffset = reminder.optionalInteger }
            case "visibility":
                entity.visibility = change.fields["visibility"]?.optionalString ?? change.visibility
            case "completion":
                if let completed = change.fields["completed"]?.optionalBoolean { entity.completed = completed }
                if let completedAt = change.fields["completedAt"] { entity.completedAt = completedAt.optionalDate }
                if let completedBy = change.fields["completedBy"] { entity.completedBy = completedBy.optionalString }
            default: continue
            }
            clocks[group] = remoteClock
        }
        entity.fieldClocksData = try Self.encode(clocks)
        entity.updatedAt = clocks.values.max()?.date ?? change.maximumClock.date
        entity.isDirty = try hasPendingOperation(entityType: SyncEntityType.todo.rawValue, entityId: entity.id)
    }

    private func applyAnniversary(_ change: RemoteEntityChange) throws {
        let existing = try anniversaryEntity(id: change.entityId)
        let coupleId = try activeCoupleId()
        let remoteClocksData = try Self.encode(change.fieldClocks)
        let entity = existing ?? LocalAnniversaryEntity(
            id: change.entityId.lowercased(),
            coupleId: coupleId,
            ownerId: change.ownerId,
            title: change.fields["title"]?.optionalString ?? "",
            date: change.fields["date"]?.optionalString ?? change.maximumClock.date.dateOnlyString,
            annual: change.fields["annual"]?.optionalBoolean ?? false,
            visibility: change.visibility,
            reminderOffset: change.fields["reminderOffset"]?.optionalInteger,
            reminderInstant: change.fields["reminderInstant"]?.optionalDate,
            createdAt: change.maximumClock.date,
            updatedAt: change.updatedAt ?? change.maximumClock.date,
            nextOccurrence: nil,
            fieldClocksData: remoteClocksData
        )
        if existing == nil { context.insert(entity) }
        if try applyLifecycle(change, entity: entity) { return }
        var clocks = try clocks(from: entity.fieldClocksData)
        for group in change.changedFieldGroups where shouldApply(group, remote: change, local: clocks) {
            switch group {
            case "content": if let value = change.fields["title"]?.optionalString { entity.title = value }
            case "schedule":
                if let value = change.fields["date"]?.optionalString { entity.date = value }
                if let value = change.fields["annual"]?.optionalBoolean { entity.annual = value }
                if let value = change.fields["reminderOffset"] { entity.reminderOffset = value.optionalInteger }
                if let value = change.fields["reminderInstant"] { entity.reminderInstant = value.optionalDate }
            case "visibility": entity.visibility = change.fields["visibility"]?.optionalString ?? change.visibility
            default: break
            }
            clocks[group] = change.fieldClocks[group]
        }
        entity.fieldClocksData = try Self.encode(clocks)
        entity.updatedAt = clocks.values.max()?.date ?? change.maximumClock.date
        entity.isDirty = try hasPendingOperation(entityType: change.entityType.rawValue, entityId: entity.id)
    }

    private func applyCalendarEvent(_ change: RemoteEntityChange) throws {
        let existing = try calendarEventEntity(id: change.entityId)
        let coupleId = try activeCoupleId()
        let remoteClocksData = try Self.encode(change.fieldClocks)
        let entity = existing ?? LocalCalendarEventEntity(
            id: change.entityId.lowercased(),
            coupleId: coupleId,
            ownerId: change.ownerId,
            title: change.fields["title"]?.optionalString ?? "",
            eventDescription: change.fields["description"]?.optionalString,
            allDay: change.fields["allDay"]?.optionalBoolean ?? false,
            startTime: change.fields["startTime"]?.optionalDate ?? change.maximumClock.date,
            endTime: change.fields["endTime"]?.optionalDate,
            timezone: change.fields["timezone"]?.optionalString ?? TimeZone.current.identifier,
            yearly: change.fields["yearly"]?.optionalBoolean ?? false,
            visibility: change.visibility,
            reminderOffset: change.fields["reminderOffset"]?.optionalInteger,
            createdAt: change.maximumClock.date,
            updatedAt: change.updatedAt ?? change.maximumClock.date,
            fieldClocksData: remoteClocksData
        )
        if existing == nil { context.insert(entity) }
        if try applyLifecycle(change, entity: entity) { return }
        var clocks = try clocks(from: entity.fieldClocksData)
        for group in change.changedFieldGroups where shouldApply(group, remote: change, local: clocks) {
            switch group {
            case "content":
                if let value = change.fields["title"]?.optionalString { entity.title = value }
                if let value = change.fields["description"] { entity.eventDescription = value.optionalString }
            case "schedule":
                if let value = change.fields["allDay"]?.optionalBoolean { entity.allDay = value }
                if let value = change.fields["startTime"]?.optionalDate { entity.startTime = value }
                if let value = change.fields["endTime"] { entity.endTime = value.optionalDate }
                if let value = change.fields["timezone"]?.optionalString { entity.timezone = value }
                if let value = change.fields["yearly"]?.optionalBoolean { entity.yearly = value }
                if let value = change.fields["reminderOffset"] { entity.reminderOffset = value.optionalInteger }
            case "visibility": entity.visibility = change.fields["visibility"]?.optionalString ?? change.visibility
            default: break
            }
            clocks[group] = change.fieldClocks[group]
        }
        entity.fieldClocksData = try Self.encode(clocks)
        entity.updatedAt = clocks.values.max()?.date ?? change.maximumClock.date
        entity.isDirty = try hasPendingOperation(entityType: change.entityType.rawValue, entityId: entity.id)
    }

    private func applyMemory(_ change: RemoteEntityChange) throws {
        let existing = try memoryEntity(id: change.entityId)
        let coupleId = try activeCoupleId()
        let remoteClocksData = try Self.encode(change.fieldClocks)
        let entity = existing ?? LocalMemoryEntity(
            id: change.entityId.lowercased(),
            coupleId: coupleId,
            ownerId: change.ownerId,
            content: change.fields["content"]?.optionalString ?? "",
            visibility: change.visibility,
            anniversaryId: change.fields["anniversaryId"]?.optionalString,
            anniversaryTitle: nil,
            todoId: change.fields["todoId"]?.optionalString,
            todoTitle: nil,
            createdAt: change.maximumClock.date,
            updatedAt: change.updatedAt ?? change.maximumClock.date,
            fieldClocksData: remoteClocksData
        )
        if existing == nil { context.insert(entity) }
        if try applyLifecycle(change, entity: entity) { return }
        var clocks = try clocks(from: entity.fieldClocksData)
        for group in change.changedFieldGroups where shouldApply(group, remote: change, local: clocks) {
            switch group {
            case "content": if let value = change.fields["content"]?.optionalString { entity.content = value }
            case "associations":
                if let value = change.fields["anniversaryId"] { entity.anniversaryId = value.optionalString }
                if let value = change.fields["todoId"] { entity.todoId = value.optionalString }
            case "visibility": entity.visibility = change.fields["visibility"]?.optionalString ?? change.visibility
            case "attachments": try applyAttachments(change.attachments, memoryId: entity.id, timelineId: nil, clock: change.maximumClock)
            default: break
            }
            clocks[group] = change.fieldClocks[group]
        }
        entity.fieldClocksData = try Self.encode(clocks)
        entity.updatedAt = clocks.values.max()?.date ?? change.maximumClock.date
        entity.isDirty = try hasPendingOperation(entityType: change.entityType.rawValue, entityId: entity.id)
    }

    private func applyTimeline(_ change: RemoteEntityChange) throws {
        let existing = try timelineEntity(id: change.entityId)
        let coupleId = try activeCoupleId()
        let remoteClocksData = try Self.encode(change.fieldClocks)
        let entity = existing ?? LocalTimelineEntity(
            id: change.entityId.lowercased(),
            coupleId: coupleId,
            ownerId: change.ownerId,
            eventDate: change.fields["eventDate"]?.optionalString ?? change.maximumClock.date.dateOnlyString,
            text: change.fields["text"]?.optionalString ?? "",
            mood: change.fields["mood"]?.optionalString,
            visibility: change.visibility,
            sortOrder: change.fields["sortOrder"]?.optionalInteger ?? 0,
            createdAt: change.maximumClock.date,
            updatedAt: change.updatedAt ?? change.maximumClock.date,
            fieldClocksData: remoteClocksData
        )
        if existing == nil { context.insert(entity) }
        if try applyLifecycle(change, entity: entity) { return }
        var clocks = try clocks(from: entity.fieldClocksData)
        for group in change.changedFieldGroups where shouldApply(group, remote: change, local: clocks) {
            switch group {
            case "content":
                if let value = change.fields["text"]?.optionalString { entity.text = value }
                if let value = change.fields["mood"] { entity.mood = value.optionalString }
            case "schedule":
                if let value = change.fields["eventDate"]?.optionalString { entity.eventDate = value }
                if let value = change.fields["sortOrder"]?.optionalInteger { entity.sortOrder = value }
            case "visibility": entity.visibility = change.fields["visibility"]?.optionalString ?? change.visibility
            case "attachments": try applyAttachments(change.attachments, memoryId: nil, timelineId: entity.id, clock: change.maximumClock)
            default: break
            }
            clocks[group] = change.fieldClocks[group]
        }
        entity.fieldClocksData = try Self.encode(clocks)
        entity.updatedAt = clocks.values.max()?.date ?? change.maximumClock.date
        entity.isDirty = try hasPendingOperation(entityType: change.entityType.rawValue, entityId: entity.id)
    }

    private func applyStandaloneAttachment(_ change: RemoteEntityChange) throws {
        guard change.kind != .delete else {
            if let entity = try attachmentEntity(id: change.entityId) {
                entity.isTombstoned = true
                entity.tombstoneClockData = try Self.encode(change.maximumClock)
            }
            return
        }
        if let existing = try attachmentEntity(id: change.entityId) {
            existing.serverId = change.entityId.lowercased()
            if let value = change.fields["filename"]?.optionalString { existing.filename = value }
            if let value = change.fields["mimeType"]?.optionalString { existing.mimeType = value }
            if let value = change.fields["size"]?.optionalInteger { existing.size = value }
            if let value = change.fields["width"] { existing.width = value.optionalInteger }
            if let value = change.fields["height"] { existing.height = value.optionalInteger }
            if let value = change.fields["durationMs"] {
                existing.durationMilliseconds = value.optionalInteger
            }
            if let value = change.fields["url"] { existing.remoteURL = value.optionalString }
            if let value = change.fields["posterUrl"] { existing.posterURL = value.optionalString }
            existing.syncState = existing.remoteURL == nil
                ? AttachmentSyncState.finalized.rawValue
                : AttachmentSyncState.remote.rawValue
            existing.isTombstoned = false
            existing.isDirty = false
            existing.updatedAt = change.maximumClock.date
            existing.fieldClocksData = try Self.encode(change.fieldClocks)
            return
        }
        context.insert(
            LocalAttachmentEntity(
                id: change.entityId.lowercased(),
                serverId: change.entityId.lowercased(),
                filename: change.fields["filename"]?.optionalString ?? change.entityId,
                mimeType: change.fields["mimeType"]?.optionalString ?? "application/octet-stream",
                size: change.fields["size"]?.optionalInteger ?? 0,
                width: change.fields["width"]?.optionalInteger,
                height: change.fields["height"]?.optionalInteger,
                durationMilliseconds: change.fields["durationMs"]?.optionalInteger,
                sortOrder: change.fields["sortOrder"]?.optionalInteger ?? 0,
                localRelativePath: nil,
                remoteURL: change.fields["url"]?.optionalString,
                posterURL: change.fields["posterUrl"]?.optionalString,
                syncState: change.fields["url"]?.optionalString == nil
                    ? AttachmentSyncState.finalized.rawValue
                    : AttachmentSyncState.remote.rawValue,
                createdAt: change.maximumClock.date,
                updatedAt: change.maximumClock.date,
                fieldClocksData: try Self.encode(change.fieldClocks)
            )
        )
    }

    private func applyLifecycle<Entity: LocalSyncLifecycle>(
        _ change: RemoteEntityChange,
        entity: Entity
    ) throws -> Bool {
        if change.kind == .delete {
            entity.isTombstoned = true
            entity.isDirty = false
            entity.tombstoneClockData = try Self.encode(change.tombstone ?? change.maximumClock)
            return true
        }
        if entity.isTombstoned, entity.tombstoneClockData == nil {
            entity.isTombstoned = false
            return false
        }
        guard entity.isTombstoned else { return false }
        guard change.kind == .restore else { return true }
        let localDelete = try entity.tombstoneClockData.map {
            try Self.decode(HybridLogicalTimestamp.self, from: $0)
        }
        guard localDelete == nil || localDelete! < change.maximumClock else { return true }
        entity.isTombstoned = false
        entity.isDirty = false
        entity.tombstoneClockData = nil
        return false
    }

    private func applyVisibilityRevocation(_ change: RemoteEntityChange) throws {
        switch change.entityType {
        case .todo:
            if let entity = try todoEntity(id: change.entityId) { markVisibilityRevoked(entity) }
        case .anniversary:
            if let entity = try anniversaryEntity(id: change.entityId) { markVisibilityRevoked(entity) }
        case .calendarEvent:
            if let entity = try calendarEventEntity(id: change.entityId) { markVisibilityRevoked(entity) }
        case .memory:
            if let entity = try memoryEntity(id: change.entityId) { markVisibilityRevoked(entity) }
        case .timeline:
            if let entity = try timelineEntity(id: change.entityId) { markVisibilityRevoked(entity) }
        case .attachment:
            if let entity = try attachmentEntity(id: change.entityId) {
                markVisibilityRevoked(entity)
            }
        }
    }

    private func markVisibilityRevoked<Entity: LocalSyncLifecycle>(_ entity: Entity) {
        entity.isTombstoned = true
        entity.tombstoneClockData = nil
    }

    private func hideCleanEntitiesMissingFromSnapshot(seen: Set<String>) throws {
        for entity in try context.fetch(FetchDescriptor<LocalTodoEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.snapshotKey(type: .todo, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try context.fetch(FetchDescriptor<LocalAnniversaryEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.snapshotKey(type: .anniversary, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try context.fetch(FetchDescriptor<LocalCalendarEventEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.snapshotKey(type: .calendarEvent, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try context.fetch(FetchDescriptor<LocalMemoryEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.snapshotKey(type: .memory, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
        for entity in try context.fetch(FetchDescriptor<LocalTimelineEntity>())
        where !entity.isDirty && !entity.isTombstoned
                && !seen.contains(Self.snapshotKey(type: .timeline, id: entity.id)) {
            markVisibilityRevoked(entity)
        }
    }

    private static func snapshotKey(type: SyncEntityType, id: String) -> String {
        "\(type.rawValue):\(id.lowercased())"
    }

    private func shouldApply(
        _ group: String,
        remote change: RemoteEntityChange,
        local clocks: [String: HybridLogicalTimestamp]
    ) -> Bool {
        guard let remoteClock = change.fieldClocks[group] else { return false }
        guard let localClock = clocks[group] else { return true }
        return localClock <= remoteClock
    }

    private func applyAttachments(
        _ remote: [RemoteAttachmentMetadata],
        memoryId: String?,
        timelineId: String?,
        clock: HybridLogicalTimestamp
    ) throws {
        let remoteIds = Set(remote.map { $0.id.lowercased() })
        let current = try context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            .filter {
                Self.identifiersEqual($0.memoryId, memoryId)
                    && Self.identifiersEqual($0.timelineId, timelineId)
            }
        for entity in current
        where entity.serverId != nil
                && !remoteIds.contains((entity.serverId ?? entity.id).lowercased()) {
            entity.isTombstoned = true
            entity.tombstoneClockData = try Self.encode(clock)
        }
        for attachment in remote {
            let matches = current.filter {
                Self.identifiersEqual($0.serverId, attachment.id)
                    || Self.identifiersEqual($0.id, attachment.id)
            }
            if let existing = Self.preferredEntity(in: matches, matching: attachment.id) {
                existing.serverId = attachment.id.lowercased()
                existing.memoryId = memoryId
                existing.timelineId = timelineId
                existing.filename = attachment.filename
                existing.mimeType = attachment.mimeType
                existing.size = attachment.size
                existing.width = attachment.width
                existing.height = attachment.height
                existing.durationMilliseconds = attachment.durationMilliseconds
                existing.sortOrder = attachment.sortOrder
                existing.remoteURL = attachment.url
                existing.posterURL = attachment.posterURL
                existing.syncState = attachment.url == nil
                    ? AttachmentSyncState.finalized.rawValue
                    : AttachmentSyncState.remote.rawValue
                existing.isTombstoned = false
                existing.updatedAt = clock.date
                continue
            }
            context.insert(
                LocalAttachmentEntity(
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
                    createdAt: clock.date,
                    updatedAt: clock.date,
                    fieldClocksData: try Self.encode(Self.clocks(groups: ["metadata"], hlc: clock))
                )
            )
        }
    }

    private func cleanReadyAttachmentFiles() async throws {
        let attachments = try context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            .filter {
                $0.localRelativePath != nil
                    && $0.remoteURL != nil
                    && $0.syncState == AttachmentSyncState.remote.rawValue
            }
        guard !attachments.isEmpty else { return }
        for attachment in attachments {
            if let path = attachment.localRelativePath {
                try await attachmentFiles.removePending(relativePath: path)
                attachment.localRelativePath = nil
            }
            attachment.uploadObjectKey = nil
            attachment.presignedUploadURL = nil
        }
        try context.save()
    }

    private func activeCoupleId() throws -> String {
        guard let session = try cachedSession(), let id = session.relationship.couple?.id else {
            return Self.activeScope
        }
        return id
    }

    private func mergeRemote(_ remote: Todo) throws {
        let remoteClock = Self.serverClock(date: remote.updatedAt)
        guard let local = try todoEntity(id: remote.id) else {
            context.insert(
                LocalTodoEntity(
                    id: remote.id.lowercased(),
                    coupleId: remote.coupleId,
                    ownerId: remote.ownerId,
                    title: remote.title,
                    note: remote.note,
                    dueTime: remote.dueTime,
                    visibility: remote.visibility.rawValue,
                    completed: remote.completed,
                    completedAt: remote.completedAt,
                    completedBy: remote.completedBy,
                    reminderOffset: remote.reminderOffset,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt,
                    fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility", "completion"], hlc: remoteClock))
                )
            )
            return
        }
        guard prepareForRemoteMerge(local) else { return }
        var clocks = try clocks(from: local.fieldClocksData)
        if clocks["content"] == nil || clocks["content"]! < remoteClock {
            local.title = remote.title
            local.note = remote.note
            clocks["content"] = remoteClock
        }
        if clocks["schedule"] == nil || clocks["schedule"]! < remoteClock {
            local.dueTime = remote.dueTime
            local.reminderOffset = remote.reminderOffset
            clocks["schedule"] = remoteClock
        }
        if clocks["completion"] == nil || clocks["completion"]! < remoteClock {
            local.completed = remote.completed
            local.completedAt = remote.completedAt
            local.completedBy = remote.completedBy
            clocks["completion"] = remoteClock
        }
        if clocks["visibility"] == nil || clocks["visibility"]! < remoteClock {
            local.visibility = remote.visibility.rawValue
            clocks["visibility"] = remoteClock
        }
        local.updatedAt = max(local.updatedAt, remote.updatedAt)
        local.fieldClocksData = try Self.encode(clocks)
    }

    private func mergeRemote(_ remote: Anniversary) throws {
        let remoteClock = Self.serverClock(date: remote.updatedAt)
        let existing = try anniversaryEntity(id: remote.id)
        guard let local = existing else {
            context.insert(
                LocalAnniversaryEntity(
                    id: remote.id.lowercased(),
                    coupleId: remote.coupleId,
                    ownerId: remote.ownerId,
                    title: remote.title,
                    date: remote.date,
                    annual: remote.annual,
                    visibility: remote.visibility.rawValue,
                    reminderOffset: remote.reminderOffset,
                    reminderInstant: remote.reminderInstant,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt,
                    nextOccurrence: remote.nextOccurrence,
                    fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility"], hlc: remoteClock))
                )
            )
            return
        }
        guard prepareForRemoteMerge(local) else { return }
        var clocks = try clocks(from: local.fieldClocksData)
        if clocks["content"] == nil || clocks["content"]! < remoteClock {
            local.title = remote.title
            clocks["content"] = remoteClock
        }
        if clocks["schedule"] == nil || clocks["schedule"]! < remoteClock {
            local.date = remote.date
            local.annual = remote.annual
            local.reminderOffset = remote.reminderOffset
            local.reminderInstant = remote.reminderInstant
            local.nextOccurrence = remote.nextOccurrence
            clocks["schedule"] = remoteClock
        }
        if clocks["visibility"] == nil || clocks["visibility"]! < remoteClock {
            local.visibility = remote.visibility.rawValue
            clocks["visibility"] = remoteClock
        }
        local.updatedAt = max(local.updatedAt, remote.updatedAt)
        local.fieldClocksData = try Self.encode(clocks)
    }

    private func mergeRemote(_ remote: CalendarEvent) throws {
        let remoteClock = Self.serverClock(date: remote.updatedAt)
        let existing = try calendarEventEntity(id: remote.id)
        guard let local = existing else {
            context.insert(
                LocalCalendarEventEntity(
                    id: remote.id.lowercased(),
                    coupleId: remote.coupleId,
                    ownerId: remote.ownerId,
                    title: remote.title,
                    eventDescription: remote.description,
                    allDay: remote.allDay,
                    startTime: remote.startTime,
                    endTime: remote.endTime,
                    timezone: remote.timezone,
                    yearly: remote.yearly,
                    visibility: remote.visibility.rawValue,
                    reminderOffset: remote.reminderOffset,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt,
                    fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility"], hlc: remoteClock))
                )
            )
            return
        }
        guard prepareForRemoteMerge(local) else { return }
        var clocks = try clocks(from: local.fieldClocksData)
        if clocks["content"] == nil || clocks["content"]! < remoteClock {
            local.title = remote.title
            local.eventDescription = remote.description
            clocks["content"] = remoteClock
        }
        if clocks["schedule"] == nil || clocks["schedule"]! < remoteClock {
            local.allDay = remote.allDay
            local.startTime = remote.startTime
            local.endTime = remote.endTime
            local.timezone = remote.timezone
            local.yearly = remote.yearly
            local.reminderOffset = remote.reminderOffset
            clocks["schedule"] = remoteClock
        }
        if clocks["visibility"] == nil || clocks["visibility"]! < remoteClock {
            local.visibility = remote.visibility.rawValue
            clocks["visibility"] = remoteClock
        }
        local.updatedAt = max(local.updatedAt, remote.updatedAt)
        local.fieldClocksData = try Self.encode(clocks)
    }

    private func mergeRemote(_ remote: Note) throws {
        let remoteClock = Self.serverClock(date: remote.updatedAt)
        let existing = try memoryEntity(id: remote.id)
        let anniversaryTitle = remote.associations.first(where: { $0.type == .anniversary })?.title
        let todoTitle = remote.associations.first(where: { $0.type == .todo })?.title
        if existing == nil {
            context.insert(
                LocalMemoryEntity(
                    id: remote.id.lowercased(),
                    coupleId: remote.coupleId,
                    ownerId: remote.ownerId,
                    content: remote.content,
                    visibility: remote.visibility.rawValue,
                    anniversaryId: remote.anniversaryId,
                    anniversaryTitle: anniversaryTitle,
                    todoId: remote.todoId,
                    todoTitle: todoTitle,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt,
                    fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "associations", "visibility", "attachments"], hlc: remoteClock))
                )
            )
        } else if let local = existing {
            guard prepareForRemoteMerge(local) else { return }
            var clocks = try clocks(from: local.fieldClocksData)
            if clocks["content"] == nil || clocks["content"]! < remoteClock {
                local.content = remote.content
                clocks["content"] = remoteClock
            }
            if clocks["associations"] == nil || clocks["associations"]! < remoteClock {
                local.anniversaryId = remote.anniversaryId
                local.anniversaryTitle = anniversaryTitle
                local.todoId = remote.todoId
                local.todoTitle = todoTitle
                clocks["associations"] = remoteClock
            }
            if clocks["visibility"] == nil || clocks["visibility"]! < remoteClock {
                local.visibility = remote.visibility.rawValue
                clocks["visibility"] = remoteClock
            }
            local.updatedAt = max(local.updatedAt, remote.updatedAt)
            local.fieldClocksData = try Self.encode(clocks)
        }
        let memoryId = existing?.id ?? remote.id.lowercased()
        for attachment in remote.attachments {
            try mergeRemote(attachment, memoryId: memoryId, hlc: remoteClock)
        }
    }

    private func mergeRemote(_ remote: TimelineEntry) throws {
        let remoteClock = Self.serverClock(date: remote.updatedAt)
        let existing = try timelineEntity(id: remote.id)
        guard let local = existing else {
            context.insert(LocalTimelineEntity(
                id: remote.id.lowercased(),
                coupleId: remote.coupleId,
                ownerId: remote.ownerId,
                eventDate: remote.eventDate,
                text: remote.text,
                mood: remote.mood,
                visibility: remote.visibility.rawValue,
                sortOrder: remote.sortOrder,
                createdAt: remote.createdAt,
                updatedAt: remote.updatedAt,
                fieldClocksData: try Self.encode(Self.clocks(groups: ["content", "schedule", "visibility", "attachments"], hlc: remoteClock))
            ))
            return
        }
        guard prepareForRemoteMerge(local) else { return }
        var clocks = try clocks(from: local.fieldClocksData)
        if clocks["content"] == nil || clocks["content"]! < remoteClock {
            local.text = remote.text
            local.mood = remote.mood
            clocks["content"] = remoteClock
        }
        if clocks["schedule"] == nil || clocks["schedule"]! < remoteClock {
            local.eventDate = remote.eventDate
            local.sortOrder = remote.sortOrder
            clocks["schedule"] = remoteClock
        }
        if clocks["visibility"] == nil || clocks["visibility"]! < remoteClock {
            local.visibility = remote.visibility.rawValue
            clocks["visibility"] = remoteClock
        }
        local.updatedAt = max(local.updatedAt, remote.updatedAt)
        local.fieldClocksData = try Self.encode(clocks)
    }

    private func prepareForRemoteMerge<Entity: LocalSyncLifecycle>(_ entity: Entity) -> Bool {
        if entity.isTombstoned, entity.tombstoneClockData == nil {
            entity.isTombstoned = false
        }
        return !entity.isTombstoned
    }

    private func mergeRemote(
        _ remote: Attachment,
        memoryId: String,
        hlc: HybridLogicalTimestamp
    ) throws {
        let existing = try attachmentEntity(id: remote.id)
        guard existing == nil else { return }
        context.insert(
            LocalAttachmentEntity(
                id: remote.id.lowercased(),
                serverId: remote.id.lowercased(),
                memoryId: memoryId,
                filename: remote.filename,
                mimeType: remote.mimeType,
                size: remote.size,
                width: remote.width,
                height: remote.height,
                durationMilliseconds: remote.durationMs,
                sortOrder: remote.sortOrder ?? 0,
                localRelativePath: nil,
                remoteURL: remote.url,
                posterURL: remote.posterUrl,
                syncState: AttachmentSyncState.remote.rawValue,
                createdAt: remote.createdAt,
                updatedAt: remote.createdAt,
                fieldClocksData: try Self.encode(Self.clocks(groups: ["metadata", "location"], hlc: hlc))
            )
        )
    }

    private func mapAttachment(_ local: LocalAttachmentEntity) async throws -> Attachment {
        let url: String?
        if let relativePath = local.localRelativePath {
            url = try await attachmentFiles.pendingFileURL(relativePath: relativePath).absoluteString
        } else {
            url = local.remoteURL
        }
        return Attachment(
            id: local.serverId ?? local.id,
            filename: local.filename,
            mimeType: local.mimeType,
            size: local.size,
            width: local.width,
            height: local.height,
            durationMs: local.durationMilliseconds,
            finalized: local.syncState == AttachmentSyncState.remote.rawValue,
            processingStatus: local.syncState,
            createdAt: local.createdAt,
            sortOrder: local.sortOrder,
            url: url,
            posterUrl: local.posterURL,
            demoAssetName: nil
        )
    }

    private func mapTodo(_ local: LocalTodoEntity) -> Todo {
        Todo(
            id: local.id,
            coupleId: local.coupleId,
            ownerId: local.ownerId,
            title: local.title,
            note: local.note,
            dueTime: local.dueTime,
            visibility: Visibility(rawValue: local.visibility) ?? .shared,
            completed: local.completed,
            completedAt: local.completedAt,
            completedBy: local.completedBy,
            reminderOffset: local.reminderOffset,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt
        )
    }

    private func mapAnniversary(_ local: LocalAnniversaryEntity) -> Anniversary {
        Anniversary(
            id: local.id,
            coupleId: local.coupleId,
            ownerId: local.ownerId,
            title: local.title,
            date: local.date,
            annual: local.annual,
            visibility: Visibility(rawValue: local.visibility) ?? .shared,
            reminderOffset: local.reminderOffset,
            reminderInstant: local.reminderInstant,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt,
            nextOccurrence: local.nextOccurrence
        )
    }

    private func mapCalendarEvent(_ local: LocalCalendarEventEntity) -> CalendarEvent {
        CalendarEvent(
            id: local.id,
            coupleId: local.coupleId,
            ownerId: local.ownerId,
            title: local.title,
            description: local.eventDescription,
            allDay: local.allDay,
            startTime: local.startTime,
            endTime: local.endTime,
            timezone: local.timezone,
            yearly: local.yearly,
            visibility: Visibility(rawValue: local.visibility) ?? .shared,
            reminderOffset: local.reminderOffset,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt,
            occurrenceId: nil,
            recurrenceSourceId: nil
        )
    }

    private func mapTimeline(_ local: LocalTimelineEntity) -> TimelineEntry {
        TimelineEntry(
            id: local.id,
            coupleId: local.coupleId,
            ownerId: local.ownerId,
            eventDate: local.eventDate,
            text: local.text,
            mood: local.mood,
            visibility: Visibility(rawValue: local.visibility) ?? .shared,
            sortOrder: local.sortOrder,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt
        )
    }

    private func enqueue(
        entityType: SyncEntityType,
        entityId: String,
        kind: MutationKind,
        payload: LocalMutationPayload,
        changedGroups: Set<String>,
        hlc: HybridLogicalTimestamp,
        now: Date
    ) throws {
        let payloadData = try Self.encode(payload)
        let overlapping = try context.fetch(FetchDescriptor<OutboxEntity>())
            .filter {
                $0.entityType == entityType.rawValue
                    && Self.identifiersEqual($0.entityId, entityId)
                    && !Set($0.changedFieldGroups).isDisjoint(with: changedGroups)
            }
            .max { $0.createdAt < $1.createdAt }
        if let existing = overlapping,
           existing.mutationKind == kind.rawValue,
           existing.payloadData == payloadData,
           Set(existing.changedFieldGroups) == changedGroups,
           existing.state != OutboxState.sending.rawValue {
            existing.state = OutboxState.pending.rawValue
            existing.nextRetryAt = nil
            existing.lastError = nil
            existing.updatedAt = now
            return
        }
        context.insert(
            OutboxEntity(
                operationId: UUID().uuidString.lowercased(),
                entityType: entityType.rawValue,
                entityId: entityId,
                mutationKind: kind.rawValue,
                payloadData: payloadData,
                changedFieldGroups: changedGroups.sorted(),
                hlcData: try Self.encode(hlc),
                createdAt: now,
                updatedAt: now
            )
        )
    }

    private func mapOperation(_ entity: OutboxEntity) throws -> PendingOperation {
        guard let type = SyncEntityType(rawValue: entity.entityType),
              let kind = MutationKind(rawValue: entity.mutationKind) else {
            throw OfflineStoreError.corruptStoredValue("outbox")
        }
        return PendingOperation(
            operationId: entity.operationId,
            entityType: type,
            entityId: entity.entityId,
            mutationKind: kind,
            payload: try Self.decode(LocalMutationPayload.self, from: entity.payloadData),
            changedFieldGroups: Set(entity.changedFieldGroups),
            hlc: try Self.decode(HybridLogicalTimestamp.self, from: entity.hlcData),
            retryCount: entity.retryCount,
            createdAt: entity.createdAt
        )
    }

    private func nextHLC(at date: Date) throws -> HybridLogicalTimestamp {
        let state = try deviceState()
        var clock = HybridLogicalClock(
            deviceId: state.deviceId,
            lastWallTimeMilliseconds: state.lastWallTimeMilliseconds,
            counter: state.counter,
            serverOffsetMilliseconds: state.serverOffsetMilliseconds
        )
        let timestamp = clock.tick(at: date)
        update(state, from: clock, at: date)
        return timestamp
    }

    private func calibrateClock(serverTime: Date, receivedAt: Date) throws {
        let state = try deviceState()
        var clock = HybridLogicalClock(
            deviceId: state.deviceId,
            lastWallTimeMilliseconds: state.lastWallTimeMilliseconds,
            counter: state.counter,
            serverOffsetMilliseconds: state.serverOffsetMilliseconds
        )
        clock.calibrate(serverTime: serverTime, receivedAt: receivedAt)
        update(state, from: clock, at: receivedAt)
    }

    private func observeClock(_ remote: HybridLogicalTimestamp, at receivedAt: Date) throws {
        let state = try deviceState()
        var clock = HybridLogicalClock(
            deviceId: state.deviceId,
            lastWallTimeMilliseconds: state.lastWallTimeMilliseconds,
            counter: state.counter,
            serverOffsetMilliseconds: state.serverOffsetMilliseconds
        )
        _ = clock.observe(remote, at: receivedAt)
        update(state, from: clock, at: receivedAt)
    }

    private func adoptAuthoritativeClock(
        _ authoritative: HybridLogicalTimestamp,
        at receivedAt: Date
    ) throws {
        let state = try deviceState()
        var clock = HybridLogicalClock(
            deviceId: state.deviceId,
            lastWallTimeMilliseconds: state.lastWallTimeMilliseconds,
            counter: state.counter,
            serverOffsetMilliseconds: state.serverOffsetMilliseconds
        )
        clock.adoptServerAdjustment(authoritative)
        update(state, from: clock, at: receivedAt)
    }

    private func deviceState() throws -> LocalDeviceStateEntity {
        if let existing = try context.fetch(FetchDescriptor<LocalDeviceStateEntity>())
            .first(where: { $0.key == "primary" }) { return existing }
        let entity = LocalDeviceStateEntity(deviceId: UUID().uuidString.lowercased())
        context.insert(entity)
        return entity
    }

    private func update(_ entity: LocalDeviceStateEntity, from clock: HybridLogicalClock, at date: Date) {
        entity.lastWallTimeMilliseconds = clock.lastWallTimeMilliseconds
        entity.counter = clock.counter
        entity.serverOffsetMilliseconds = clock.serverOffsetMilliseconds
        entity.updatedAt = date
    }

    private func recoverInterruptedOperations() throws {
        var changed = false
        for entity in try context.fetch(FetchDescriptor<OutboxEntity>())
        where entity.state == OutboxState.sending.rawValue {
            entity.state = OutboxState.pending.rawValue
            entity.updatedAt = .now
            changed = true
        }
        if changed { try context.save() }
    }

    private func repairCaseVariantDuplicates() throws {
        var changed = false
        changed = try repairCleanCaseVariantDuplicates(LocalTodoEntity.self, entityType: .todo) {
            duplicate,
            survivor in
            for memory in try self.context.fetch(FetchDescriptor<LocalMemoryEntity>())
            where Self.identifiersEqual(memory.todoId, duplicate.id) {
                memory.todoId = survivor.id
            }
        } || changed
        changed = try repairCleanCaseVariantDuplicates(LocalAnniversaryEntity.self, entityType: .anniversary) {
            duplicate,
            survivor in
            for memory in try self.context.fetch(FetchDescriptor<LocalMemoryEntity>())
            where Self.identifiersEqual(memory.anniversaryId, duplicate.id) {
                memory.anniversaryId = survivor.id
            }
        } || changed
        changed = try repairCleanCaseVariantDuplicates(LocalCalendarEventEntity.self, entityType: .calendarEvent) {
            _, _ in
        } || changed
        changed = try repairCleanCaseVariantDuplicates(LocalMemoryEntity.self, entityType: .memory) {
            duplicate,
            survivor in
            for attachment in try self.context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            where Self.identifiersEqual(attachment.memoryId, duplicate.id) {
                attachment.memoryId = survivor.id
            }
        } || changed
        changed = try repairCleanCaseVariantDuplicates(LocalTimelineEntity.self, entityType: .timeline) {
            duplicate,
            survivor in
            for attachment in try self.context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            where Self.identifiersEqual(attachment.timelineId, duplicate.id) {
                attachment.timelineId = survivor.id
            }
        } || changed
        if changed { try context.save() }
    }

    private func repairCleanCaseVariantDuplicates<Entity>(
        _ type: Entity.Type,
        entityType: SyncEntityType,
        rewireReferences: (Entity, Entity) throws -> Void
    ) throws -> Bool where Entity: PersistentModel & LocalSyncEntity {
        let entities = try context.fetch(FetchDescriptor<Entity>())
        let outbox = try context.fetch(FetchDescriptor<OutboxEntity>())
        let groups = Dictionary(grouping: entities) { $0.id.lowercased() }
        var changed = false

        for (canonicalID, variants) in groups where variants.count > 1 {
            let hasOperation = outbox.contains {
                $0.entityType == entityType.rawValue
                    && Self.identifiersEqual($0.entityId, canonicalID)
            }
            guard !hasOperation, variants.allSatisfy({ !$0.isDirty }),
                  let survivor = Self.preferredEntity(in: variants, matching: canonicalID) else {
                continue
            }
            for duplicate in variants where duplicate.id != survivor.id {
                try rewireReferences(duplicate, survivor)
                context.delete(duplicate)
                changed = true
            }
        }
        return changed
    }

    private func metadata() throws -> SyncMetadataEntity? {
        try context.fetch(FetchDescriptor<SyncMetadataEntity>())
            .first(where: { $0.scopeId == Self.activeScope })
    }

    private func updateMetadata(
        cursor: String?,
        bootstrapCompleted: Bool,
        serverTime: Date?,
        successfulSyncAt: Date? = nil
    ) throws {
        let entity: SyncMetadataEntity
        if let existing = try metadata() {
            entity = existing
        } else {
            entity = SyncMetadataEntity(scopeId: Self.activeScope)
            context.insert(entity)
        }
        entity.cursor = cursor
        entity.bootstrapCompleted = bootstrapCompleted
        if let serverTime { entity.lastServerTime = serverTime }
        if let successfulSyncAt { entity.lastSuccessfulSyncAt = successfulSyncAt }
    }

    private static func identifiersEqual(_ left: String?, _ right: String?) -> Bool {
        guard let left, let right else { return left == nil && right == nil }
        return left.lowercased() == right.lowercased()
    }

    private static func preferredEntity<Entity: LocalSyncEntity>(
        in entities: [Entity],
        matching id: String
    ) -> Entity? {
        entities.max { left, right in
            if left.isDirty != right.isDirty { return !left.isDirty && right.isDirty }
            let leftIsExact = left.id == id
            let rightIsExact = right.id == id
            if leftIsExact != rightIsExact { return !leftIsExact && rightIsExact }
            return left.updatedAt < right.updatedAt
        }
    }

    private static func deduplicatedEntities<Entity: LocalSyncEntity>(
        _ entities: [Entity]
    ) -> [Entity] {
        Dictionary(grouping: entities) { $0.id.lowercased() }
            .compactMap { canonicalID, variants in
                preferredEntity(in: variants, matching: canonicalID)
            }
    }

    private func entity<Entity>(
        _ type: Entity.Type,
        id: String
    ) throws -> Entity? where Entity: PersistentModel & LocalSyncEntity {
        let matches = try context.fetch(FetchDescriptor<Entity>())
            .filter { Self.identifiersEqual($0.id, id) }
        return Self.preferredEntity(in: matches, matching: id)
    }

    private func todoEntity(id: String) throws -> LocalTodoEntity? {
        try entity(LocalTodoEntity.self, id: id)
    }

    private func anniversaryEntity(id: String) throws -> LocalAnniversaryEntity? {
        try entity(LocalAnniversaryEntity.self, id: id)
    }

    private func calendarEventEntity(id: String) throws -> LocalCalendarEventEntity? {
        try entity(LocalCalendarEventEntity.self, id: id)
    }

    private func memoryEntity(id: String) throws -> LocalMemoryEntity? {
        try entity(LocalMemoryEntity.self, id: id)
    }

    private func timelineEntity(id: String) throws -> LocalTimelineEntity? {
        try entity(LocalTimelineEntity.self, id: id)
    }

    private func attachmentEntity(id: String) throws -> LocalAttachmentEntity? {
        let matches = try context.fetch(FetchDescriptor<LocalAttachmentEntity>())
            .filter {
                Self.identifiersEqual($0.id, id)
                    || Self.identifiersEqual($0.serverId, id)
            }
        return Self.preferredEntity(in: matches, matching: id)
    }

    private func resetFieldClocks(
        entityType: SyncEntityType?,
        entityId: String,
        to clocks: Data
    ) throws {
        let entity: (any LocalSyncLifecycle)? = switch entityType {
        case .todo: try todoEntity(id: entityId)
        case .anniversary: try anniversaryEntity(id: entityId)
        case .calendarEvent: try calendarEventEntity(id: entityId)
        case .memory: try memoryEntity(id: entityId)
        case .timeline: try timelineEntity(id: entityId)
        case .attachment, nil: nil
        }
        entity?.fieldClocksData = clocks
        entity?.isDirty = false
    }

    private func setClock<Entity: LocalSyncLifecycle>(
        _ hlc: HybridLogicalTimestamp,
        group: String,
        on entity: Entity
    ) throws {
        try setClock(hlc, groups: [group], on: entity)
    }

    private func setClock<Entity: LocalSyncLifecycle>(
        _ hlc: HybridLogicalTimestamp,
        groups: Set<String>,
        on entity: Entity
    ) throws {
        var clocks = try clocks(from: entity.fieldClocksData)
        for group in groups { clocks[group] = hlc }
        entity.fieldClocksData = try Self.encode(clocks)
    }

    private func delete<Entity: LocalSyncEntity>(
        _ entity: Entity,
        entityType: SyncEntityType,
        now: Date
    ) throws {
        guard !entity.isTombstoned else { return }
        let hlc = try nextHLC(at: now)
        entity.isTombstoned = true
        entity.isDirty = true
        entity.tombstoneClockData = try Self.encode(hlc)
        entity.updatedAt = now
        try enqueue(
            entityType: entityType,
            entityId: entity.id,
            kind: .delete,
            payload: .init(fields: [:]),
            changedGroups: ["lifecycle"],
            hlc: hlc,
            now: now
        )
        try context.save()
    }

    private func clocks(from data: Data) throws -> [String: HybridLogicalTimestamp] {
        try Self.decode([String: HybridLogicalTimestamp].self, from: data)
    }

    private func hasPendingOperation(entityType: String, entityId: String) throws -> Bool {
        try context.fetch(FetchDescriptor<OutboxEntity>())
            .contains {
                $0.entityType == entityType
                    && Self.identifiersEqual($0.entityId, entityId)
            }
    }

    private func isLocallyTombstoned(entityType: String, entityId: String) throws -> Bool {
        switch SyncEntityType(rawValue: entityType) {
        case .todo: try todoEntity(id: entityId)?.tombstoneClockData != nil
        case .anniversary: try anniversaryEntity(id: entityId)?.tombstoneClockData != nil
        case .calendarEvent: try calendarEventEntity(id: entityId)?.tombstoneClockData != nil
        case .memory: try memoryEntity(id: entityId)?.tombstoneClockData != nil
        case .timeline: try timelineEntity(id: entityId)?.tombstoneClockData != nil
        case .attachment: try attachmentEntity(id: entityId)?.tombstoneClockData != nil
        case nil: false
        }
    }

    private func markEntityClean(entityType: String, entityId: String) throws {
        switch SyncEntityType(rawValue: entityType) {
        case .todo: try todoEntity(id: entityId)?.isDirty = false
        case .anniversary: try anniversaryEntity(id: entityId)?.isDirty = false
        case .calendarEvent: try calendarEventEntity(id: entityId)?.isDirty = false
        case .memory: try memoryEntity(id: entityId)?.isDirty = false
        case .timeline: try timelineEntity(id: entityId)?.isDirty = false
        case .attachment: try attachmentEntity(id: entityId)?.isDirty = false
        case nil: break
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for entity in try context.fetch(FetchDescriptor<T>()) { context.delete(entity) }
    }

    private func todoPayload(_ entity: LocalTodoEntity) -> LocalMutationPayload {
        .init(fields: [
            "title": .string(entity.title),
            "note": entity.note.map(MutationValue.string) ?? .null,
            "dueTime": entity.dueTime.map(MutationValue.date) ?? .null,
            "visibility": .string(entity.visibility),
            "completed": .boolean(entity.completed),
            "reminderOffset": entity.reminderOffset.map(MutationValue.integer) ?? .null,
        ])
    }

    private func anniversaryPayload(_ entity: LocalAnniversaryEntity) -> LocalMutationPayload {
        .init(fields: [
            "title": .string(entity.title),
            "date": .string(entity.date),
            "annual": .boolean(entity.annual),
            "visibility": .string(entity.visibility),
            "reminderOffset": entity.reminderOffset.map(MutationValue.integer) ?? .null,
            "reminderInstant": entity.reminderInstant.map(MutationValue.date) ?? .null,
        ])
    }

    private func calendarPayload(_ entity: LocalCalendarEventEntity) -> LocalMutationPayload {
        .init(fields: [
            "title": .string(entity.title),
            "description": entity.eventDescription.map(MutationValue.string) ?? .null,
            "allDay": .boolean(entity.allDay),
            "startTime": .date(entity.startTime),
            "endTime": entity.endTime.map(MutationValue.date) ?? .null,
            "timezone": .string(entity.timezone),
            "yearly": .boolean(entity.yearly),
            "visibility": .string(entity.visibility),
            "reminderOffset": entity.reminderOffset.map(MutationValue.integer) ?? .null,
        ])
    }

    private func memoryPayload(_ entity: LocalMemoryEntity) -> LocalMutationPayload {
        .init(fields: [
            "content": .string(entity.content),
            "visibility": .string(entity.visibility),
            "anniversaryId": entity.anniversaryId.map(MutationValue.string) ?? .null,
            "todoId": entity.todoId.map(MutationValue.string) ?? .null,
            "attachmentIds": .strings([]),
        ])
    }

    private func timelinePayload(_ entity: LocalTimelineEntity) -> LocalMutationPayload {
        .init(fields: [
            "text": .string(entity.text),
            "mood": entity.mood.map(MutationValue.string) ?? .null,
            "eventDate": .string(entity.eventDate),
            "sortOrder": .integer(entity.sortOrder),
            "visibility": .string(entity.visibility),
            "attachmentIds": .strings([]),
        ])
    }

    private static func clocks(
        groups: [String],
        hlc: HybridLogicalTimestamp
    ) -> [String: HybridLogicalTimestamp] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0, hlc) })
    }

    private static func serverClock(date: Date) -> HybridLogicalTimestamp {
        HybridLogicalTimestamp(
            wallTimeMilliseconds: date.millisecondsSince1970,
            counter: 0,
            deviceId: "server"
        )
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

struct LocalPendingAttachment: Equatable, Sendable {
    let localId: String
    let serverId: String?
    let filename: String
    let mimeType: String
    let size: Int
    let width: Int?
    let height: Int?
    let syncState: String
    let uploadObjectKey: String?
    let presignedUploadURL: String?
    let relativePath: String
}

private extension MutationValue {
    var optionalString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var optionalDate: Date? {
        if case .date(let value) = self { return value }
        return nil
    }

    var optionalInteger: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var optionalBoolean: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }
}

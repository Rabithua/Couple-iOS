import Foundation
import SwiftData
import XCTest
@testable import Couple

@MainActor
final class OfflineSyncTests: XCTestCase {
    func testSystemBirthdayPersistsKindAndOnlyEnqueuesDateEdit() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalDate = Date(timeIntervalSince1970: 965_433_600)
        let updatedDate = originalDate.addingTimeInterval(86_400)
        let birthday = Anniversary(
            id: UUID().uuidString.lowercased(),
            coupleId: UUID().uuidString.lowercased(),
            ownerId: UUID().uuidString.lowercased(),
            title: "程袭",
            date: originalDate.dateOnlyString,
            annual: true,
            visibility: .shared,
            reminderEnabled: true,
            reminderOffset: 1_440,
            reminderLocalTime: "09:00",
            reminderInstant: nil,
            createdAt: .now,
            updatedAt: .now,
            nextOccurrence: nil,
            systemKind: "birthday"
        )
        try store.bootstrap(
            notes: [],
            todos: [],
            anniversaries: [birthday],
            calendarEvents: []
        )

        try store.editSystemBirthdayDate(id: birthday.id, date: updatedDate)

        let snapshot = try await store.loadSnapshot()
        let saved = try XCTUnwrap(snapshot.anniversaries.first)
        XCTAssertEqual(saved.systemKind, "birthday")
        XCTAssertEqual(saved.title, "程袭")
        XCTAssertEqual(saved.date, updatedDate.dateOnlyString)
        let operations = try await store.pendingOperations(limit: 10, now: .distantFuture)
        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.changedFieldGroups, ["schedule"])
        XCTAssertEqual(operation.payload.fields, ["date": .string(updatedDate.dateOnlyString)])
    }

    func testCreateTodoPersistsDueDateAndIncludesItInSyncPayload() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let dueDate = Date(timeIntervalSince1970: 1_786_803_600)

        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "带日期的清单",
            dueDate: dueDate,
            visibility: .shared
        )

        XCTAssertEqual(todo.dueTime, dueDate)
        let snapshot = try await store.loadSnapshot()
        XCTAssertEqual(snapshot.todos.first(where: { $0.id == todo.id })?.dueTime, dueDate)
        let operations = try await store.pendingOperations(limit: 100, now: .distantFuture)
        let createOperation = try XCTUnwrap(operations.first(where: { $0.entityId == todo.id }))
        XCTAssertEqual(createOperation.payload.fields["dueTime"], .date(dueDate))
    }

    func testUserCreatedContentCanBeEditedAndDeletedThroughSyncOutbox() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalDate = Date(timeIntervalSince1970: 1_786_800_000)
        let updatedDate = originalDate.addingTimeInterval(86_400)

        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "原清单",
            dueDate: originalDate,
            visibility: .shared
        )
        let anniversary = try store.createAnniversary(
            coupleId: "couple",
            ownerId: "owner",
            title: "原纪念日",
            date: originalDate,
            annual: true,
            visibility: .shared
        )
        let event = try store.createCalendarEvent(
            coupleId: "couple",
            ownerId: "owner",
            title: "原日程",
            start: originalDate,
            end: originalDate.addingTimeInterval(3_600),
            allDay: false
        )
        let note = try await store.createMemory(
            coupleId: "couple",
            ownerId: "owner",
            content: "原动态",
            photos: [],
            anniversaryId: anniversary.id,
            anniversaryTitle: anniversary.title,
            todoId: todo.id,
            todoTitle: todo.title,
            visibility: .shared
        )
        let creates = try await store.pendingOperations(limit: 100, now: .distantFuture)
        try await store.acknowledge(operationIds: creates.map(\.operationId), now: .now)

        try store.editTodo(
            id: todo.id,
            title: "新清单",
            dueDate: updatedDate,
            visibility: .private
        )
        try store.editAnniversary(
            id: anniversary.id,
            title: "新纪念日",
            date: updatedDate,
            annual: false,
            visibility: .private
        )
        try store.editCalendarEvent(
            id: event.id,
            title: "新日程",
            start: updatedDate,
            end: updatedDate.addingTimeInterval(7_200),
            allDay: true
        )
        try store.editMemory(
            id: note.id,
            content: "新动态",
            anniversaryId: nil,
            anniversaryTitle: nil,
            todoId: nil,
            todoTitle: nil,
            visibility: .private
        )

        let edited = try await store.loadSnapshot()
        XCTAssertEqual(edited.todos.first?.title, "新清单")
        XCTAssertEqual(edited.todos.first?.dueTime, updatedDate)
        XCTAssertEqual(edited.todos.first?.visibility, .private)
        XCTAssertEqual(edited.anniversaries.first?.title, "新纪念日")
        XCTAssertEqual(edited.anniversaries.first?.date, updatedDate.dateOnlyString)
        XCTAssertEqual(edited.anniversaries.first?.annual, false)
        XCTAssertEqual(edited.canonicalCalendarEvents.first?.title, "新日程")
        XCTAssertEqual(edited.canonicalCalendarEvents.first?.startTime, updatedDate)
        XCTAssertEqual(edited.canonicalCalendarEvents.first?.allDay, true)
        XCTAssertEqual(edited.notes.first?.content, "新动态")
        XCTAssertEqual(edited.notes.first?.visibility, .private)
        XCTAssertTrue(edited.notes.first?.associations.isEmpty == true)

        let updates = try await store.pendingOperations(limit: 100, now: .distantFuture)
        XCTAssertEqual(updates.count, 4)
        XCTAssertTrue(updates.allSatisfy { $0.mutationKind == .update })
        XCTAssertEqual(Set(updates.map(\.entityType)), [.todo, .anniversary, .calendarEvent, .memory])
        let deviceID = UUID().uuidString
        for operation in updates {
            XCTAssertNoThrow(try SyncV1Mutation(operation: operation, deviceId: deviceID))
        }
        try await store.acknowledge(operationIds: updates.map(\.operationId), now: .now)

        try store.deleteTodo(id: todo.id)
        try store.deleteAnniversary(id: anniversary.id)
        try store.deleteCalendarEvent(id: event.id)
        try await store.deleteMemory(id: note.id)

        let deleted = try await store.loadSnapshot()
        XCTAssertTrue(deleted.todos.isEmpty)
        XCTAssertTrue(deleted.anniversaries.isEmpty)
        XCTAssertTrue(deleted.canonicalCalendarEvents.isEmpty)
        XCTAssertTrue(deleted.notes.isEmpty)
        let deletes = try await store.pendingOperations(limit: 100, now: .distantFuture)
        XCTAssertEqual(deletes.count, 4)
        XCTAssertTrue(deletes.allSatisfy { $0.mutationKind == .delete })
        XCTAssertTrue(deletes.allSatisfy { $0.changedFieldGroups == ["lifecycle"] })
        for operation in deletes {
            XCTAssertNoThrow(try SyncV1Mutation(operation: operation, deviceId: deviceID))
        }
    }

    func testNewIdentifiersAreLowercaseAndRemoteCaseVariantsMergeIntoOneEntity() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "大小写兼容",
            dueDate: nil,
            visibility: .shared
        )
        XCTAssertEqual(todo.id, todo.id.lowercased())

        let pending = try await store.pendingOperations(limit: 100, now: .distantFuture)
        try await store.acknowledge(operationIds: pending.map(\.operationId), now: .now)
        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: Date.now.millisecondsSince1970 + 10_000,
            counter: 0,
            deviceId: "server"
        )
        try await store.applyRemotePage(
            PullPage(
                changes: [remoteTodo(
                    id: todo.id.uppercased(),
                    kind: .upsert,
                    fields: ["completed": .boolean(true)],
                    groups: ["completion"],
                    clock: clock
                )],
                nextCursor: "case-variant",
                hasMore: false,
                serverTime: .now
            ),
            now: .now
        )

        let snapshot = try await store.loadSnapshot()
        XCTAssertEqual(snapshot.todos.count, 1)
        XCTAssertEqual(snapshot.todos.first?.id, todo.id)
        XCTAssertEqual(snapshot.todos.first?.completed, true)
    }

    func testOpeningStoreRepairsCleanUUIDCaseVariantDuplicates() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appending(path: "offline.store")
        let canonicalID = "0754cf6a-b9e6-47d5-99ae-6e965c258fc2"
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let clocks = try JSONEncoder().encode([String: HybridLogicalTimestamp]())

        do {
            let schema = Schema(OfflineSchema.models)
            let configuration = ModelConfiguration(
                "CoupleOfflineTests",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(LocalTodoEntity(
                id: canonicalID.uppercased(),
                coupleId: "couple",
                ownerId: "owner",
                title: "历史重复",
                note: nil,
                dueTime: nil,
                visibility: Visibility.shared.rawValue,
                completed: false,
                completedAt: nil,
                completedBy: nil,
                reminderOffset: nil,
                createdAt: olderDate,
                updatedAt: olderDate,
                fieldClocksData: clocks
            ))
            context.insert(LocalTodoEntity(
                id: canonicalID,
                coupleId: "couple",
                ownerId: "owner",
                title: "历史重复",
                note: nil,
                dueTime: nil,
                visibility: Visibility.shared.rawValue,
                completed: true,
                completedAt: newerDate,
                completedBy: "owner",
                reminderOffset: nil,
                createdAt: olderDate,
                updatedAt: newerDate,
                fieldClocksData: clocks
            ))
            try context.save()
        }

        var store: OfflineStore? = try OfflineStore.makePersistent(
            storeURL: storeURL,
            attachmentRoot: root.appending(path: "attachments")
        )
        let snapshot = try await store?.loadSnapshot()
        XCTAssertEqual(snapshot?.todos.count, 1)
        XCTAssertEqual(snapshot?.todos.first?.id, canonicalID)
        XCTAssertEqual(snapshot?.todos.first?.completed, true)
        store = nil

        let schema = Schema(OfflineSchema.models)
        let configuration = ModelConfiguration(
            "CoupleOfflineTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalTodoEntity>()).count, 1)
    }

    func testSwiftDataCRUDAndRestartPersistence() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appending(path: "offline.store")
        var first: OfflineStore? = try OfflineStore.makePersistent(
            storeURL: storeURL,
            attachmentRoot: root.appending(path: "attachments")
        )
        let todo = try first!.createTodo(
            coupleId: SampleData.relationship.couple!.id,
            ownerId: SampleData.user.id,
            title: "离线清单",
            dueDate: nil,
            visibility: .shared
        )
        try first!.editTodoTitle(id: todo.id, title: "重启后仍存在")
        let beforeRestart = try await first!.loadSnapshot()
        XCTAssertEqual(beforeRestart.todos.first?.title, "重启后仍存在")
        first = nil

        let reopened = try OfflineStore.makePersistent(
            storeURL: storeURL,
            attachmentRoot: root.appending(path: "attachments")
        )
        let snapshot = try await reopened.loadSnapshot()
        XCTAssertEqual(snapshot.todos.map(\.title), ["重启后仍存在"])
        XCTAssertEqual(try reopened.unsyncedCount(), 2)
    }

    func testIdenticalOutboxMutationIsCoalescedAndOperationIdIsStable() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "最初",
            dueDate: nil,
            visibility: .shared
        )
        try store.editTodoTitle(id: todo.id, title: "相同内容")
        let before = try await store.pendingOperations(limit: 100, now: .distantFuture)
        try store.editTodoTitle(id: todo.id, title: "相同内容")
        let after = try await store.pendingOperations(limit: 100, now: .distantFuture)

        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(Set(before.map(\.operationId)), Set(after.map(\.operationId)))
    }

    func testReturningToEarlierPayloadCreatesNewerOperationInsteadOfReusingStaleHLC() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "初始",
            dueDate: nil,
            visibility: .shared
        )
        try store.editTodoTitle(id: todo.id, title: "B")
        try store.editTodoTitle(id: todo.id, title: "C")
        try store.editTodoTitle(id: todo.id, title: "B")

        let operations = try await store.pendingOperations(limit: 100, now: .distantFuture)
        let titleBOperations = operations.filter { $0.payload.fields["title"] == .string("B") }
        XCTAssertEqual(operations.count, 4)
        XCTAssertEqual(titleBOperations.count, 2)
        XCTAssertLessThan(
            try XCTUnwrap(titleBOperations.first?.hlc),
            try XCTUnwrap(titleBOperations.last?.hlc)
        )
    }

    func testHLCIsMonotonicAcrossClockRollbackAndRemoteObservation() {
        let base = Date(timeIntervalSince1970: 1_000)
        var clock = HybridLogicalClock(deviceId: "device")
        let first = clock.tick(at: base)
        let second = clock.tick(at: base)
        let third = clock.tick(at: base.addingTimeInterval(-100))
        let remote = HybridLogicalTimestamp(
            wallTimeMilliseconds: third.wallTimeMilliseconds + 10,
            counter: 8,
            deviceId: "remote"
        )
        let observed = clock.observe(remote, at: base)

        XCTAssertLessThan(first, second)
        XCTAssertLessThan(second, third)
        XCTAssertGreaterThan(observed, remote)
    }

    func testServerClockClampRebasesFutureDeviceClockForNextMutation() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let serverNow = Date(timeIntervalSince1970: 1_786_435_200)
        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "未来时钟操作",
            dueDate: nil,
            visibility: .shared,
            now: serverNow.addingTimeInterval(3_600)
        )
        let first = try await store.pendingOperations(limit: 1, now: .distantFuture)
        try await store.acknowledge(operationIds: first.map(\.operationId), now: serverNow)
        let authoritative = HybridLogicalTimestamp(
            wallTimeMilliseconds: serverNow.millisecondsSince1970,
            counter: 4,
            deviceId: "server"
        )
        try await store.applyRemotePage(
            PullPage(
                changes: [],
                nextCursor: "clock-adjusted",
                hasMore: false,
                serverTime: serverNow,
                authoritativeClock: authoritative,
                shouldAdoptAuthoritativeClock: true
            ),
            now: serverNow
        )

        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "校准后的操作",
            dueDate: nil,
            visibility: .shared,
            now: serverNow
        )
        let rebasedOperations = try await store.pendingOperations(limit: 1, now: .distantFuture)
        let rebased = try XCTUnwrap(rebasedOperations.first)
        XCTAssertEqual(rebased.hlc.wallTimeMilliseconds, serverNow.millisecondsSince1970)
        XCTAssertEqual(rebased.hlc.counter, 5)
    }

    func testOfflineCreateEditDeleteAndDeleteWinsOverLateEdit() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "离线创建",
            dueDate: nil,
            visibility: .shared
        )
        try store.editTodoTitle(id: todo.id, title: "离线编辑")
        try store.deleteTodo(id: todo.id)
        let deletedSnapshot = try await store.loadSnapshot()
        XCTAssertTrue(deletedSnapshot.todos.isEmpty)

        let lateClock = HybridLogicalTimestamp(
            wallTimeMilliseconds: Date.now.millisecondsSince1970 + 100_000,
            counter: 0,
            deviceId: "other"
        )
        try await store.applyRemotePage(
            PullPage(
                changes: [remoteTodo(
                    id: todo.id,
                    kind: .upsert,
                    fields: ["title": .string("晚到编辑")],
                    groups: ["content"],
                    clock: lateClock
                )],
                nextCursor: "late",
                hasMore: false,
                serverTime: .now
            ),
            now: .now
        )
        let afterLateEdit = try await store.loadSnapshot()
        XCTAssertTrue(afterLateEdit.todos.isEmpty)
    }

    func testSnapshotReconciliationIsAtomicAndVisibilityRevocationCanReappear() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = makeTodo(title: "仍可见")
        let stale = makeTodo(title: "已改为私密")
        try store.bootstrap(
            notes: [],
            todos: [retained, stale],
            anniversaries: [],
            calendarEvents: []
        )
        let dirty = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "未上传本地创建",
            dueDate: nil,
            visibility: .shared
        )
        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: Date.now.millisecondsSince1970 + 10_000,
            counter: 0,
            deviceId: "server"
        )

        try await store.applyRemotePage(
            PullPage(
                changes: [remoteTodo(
                    id: retained.id,
                    kind: .upsert,
                    fields: ["title": .string(retained.title)],
                    groups: ["content"],
                    clock: clock
                )],
                nextCursor: "snapshot-page-2",
                hasMore: true,
                serverTime: .now,
                mode: .snapshot
            ),
            now: .now
        )
        let firstPageSnapshot = try await store.loadSnapshot()
        XCTAssertEqual(
            Set(firstPageSnapshot.todos.map(\.id)),
            [retained.id.lowercased(), stale.id.lowercased(), dirty.id]
        )

        try await store.applyRemotePage(
            PullPage(
                changes: [],
                nextCursor: "incremental-cursor",
                hasMore: false,
                serverTime: .now,
                mode: .snapshot
            ),
            now: .now
        )
        let completedSnapshot = try await store.loadSnapshot()
        XCTAssertEqual(Set(completedSnapshot.todos.map(\.id)), [retained.id.lowercased(), dirty.id])

        let resharedClock = HybridLogicalTimestamp(
            wallTimeMilliseconds: clock.wallTimeMilliseconds + 1,
            counter: 0,
            deviceId: "server"
        )
        try await store.applyRemotePage(
            PullPage(
                changes: [remoteTodo(
                    id: stale.id,
                    kind: .upsert,
                    fields: ["title": .string("重新共享")],
                    groups: ["content"],
                    clock: resharedClock
                )],
                nextCursor: "after-reshare",
                hasMore: false,
                serverTime: .now
            ),
            now: .now
        )
        let resharedSnapshot = try await store.loadSnapshot()
        XCTAssertTrue(resharedSnapshot.todos.contains(where: { $0.id == stale.id.lowercased() }))

        let revoked = RemoteEntityChange(
            entityType: .todo,
            entityId: stale.id,
            ownerId: "owner",
            visibility: Visibility.private.rawValue,
            kind: .delete,
            fields: [:],
            attachments: [],
            changedFieldGroups: ["lifecycle"],
            fieldClocks: [:],
            tombstone: resharedClock,
            updatedAt: resharedClock.date,
            reason: "visibilityRevoked"
        )
        try await store.applyRemotePage(
            PullPage(
                changes: [revoked],
                nextCursor: "revoked",
                hasMore: false,
                serverTime: .now
            ),
            now: .now
        )
        let revokedSnapshot = try await store.loadSnapshot()
        XCTAssertFalse(revokedSnapshot.todos.contains(where: { $0.id == stale.id }))
    }

    func testFailurePersistsExponentialRetryState() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "重试",
            dueDate: nil,
            visibility: .shared
        )
        let now = Date()
        let pending = try await store.pendingOperations(limit: 1, now: now)
        let operation = try XCTUnwrap(pending.first)
        try await store.markSending(operationIds: [operation.operationId], now: now)
        try await store.fail(
            operationIds: [operation.operationId],
            message: "offline",
            now: now,
            retryBaseDelay: 2
        )
        let tooEarly = try await store.pendingOperations(limit: 1, now: now.addingTimeInterval(1))
        XCTAssertTrue(tooEarly.isEmpty)
        let retried = try await store.pendingOperations(limit: 1, now: now.addingTimeInterval(2.1))
        XCTAssertEqual(retried.first?.retryCount, 1)
        XCTAssertEqual(retried.first?.operationId, operation.operationId)
    }

    func testNonRetryableMutationRemainsForUserResolutionWithoutBeingResent() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "服务器拒绝",
            dueDate: nil,
            visibility: .shared
        )
        let transport = RejectingSyncTransport()
        let coordinator = SyncCoordinator(store: store, transport: transport)

        let first = await coordinator.trigger(.manual)
        let second = await coordinator.trigger(.retry)

        guard case .failed = first else { return XCTFail("first run should surface rejection") }
        XCTAssertEqual(second, .success)
        XCTAssertEqual(try store.unsyncedCount(), 1)
        let remainingPending = try await store.pendingOperations(limit: 100, now: .distantFuture)
        let mutationCalls = await transport.mutationExchangeCount()
        XCTAssertTrue(remainingPending.isEmpty)
        XCTAssertEqual(mutationCalls, 1)
    }

    func testTombstoneConflictPullsFinalStateWithoutDroppingOtherOutboxData() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = Todo(
            id: UUID().uuidString,
            coupleId: "couple",
            ownerId: "owner",
            title: "远端将删除",
            note: nil,
            dueTime: nil,
            visibility: .shared,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: nil,
            createdAt: .now,
            updatedAt: .now
        )
        try store.bootstrap(notes: [], todos: [todo], anniversaries: [], calendarEvents: [])
        try store.editTodoTitle(id: todo.id, title: "晚到本地编辑")
        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "不相关操作",
            dueDate: nil,
            visibility: .shared
        )
        let transport = TombstoneConflictTransport(deletedId: todo.id)
        let coordinator = SyncCoordinator(store: store, transport: transport)

        let result = await coordinator.trigger(.manual)
        XCTAssertEqual(result, .success)
        let snapshot = try await store.loadSnapshot()
        XCTAssertFalse(snapshot.todos.contains(where: { $0.id == todo.id }))
        XCTAssertTrue(snapshot.todos.contains(where: { $0.title == "不相关操作" }))
        XCTAssertEqual(try store.unsyncedCount(), 0)
    }

    func testCoordinatorIsSingleFlightAndCancellationIsCooperative() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SlowSyncTransport(delay: .milliseconds(150))
        let coordinator = SyncCoordinator(store: store, transport: transport)

        async let launch = coordinator.trigger(.launch)
        try await Task.sleep(for: .milliseconds(20))
        async let foreground = coordinator.trigger(.foreground)
        let firstResults = await (launch, foreground)
        XCTAssertEqual(firstResults.0, .success)
        XCTAssertEqual(firstResults.1, .success)
        let exchangeCount = await transport.exchangeCount()
        XCTAssertEqual(exchangeCount, 1)

        let cancellableTransport = SlowSyncTransport(delay: .seconds(5))
        let cancellable = SyncCoordinator(store: store, transport: cancellableTransport)
        let task = Task { await cancellable.trigger(.manual) }
        try await Task.sleep(for: .milliseconds(30))
        await cancellable.cancel()
        let cancelledResult = await task.value
        XCTAssertEqual(cancelledResult, .cancelled)
    }

    func testWriteTriggeredWhileAnEmptyRunFinishesIsNotLost() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SlowSyncTransport(delay: .milliseconds(120))
        let coordinator = SyncCoordinator(store: store, transport: transport)

        async let launch = coordinator.trigger(.launch)
        try await Task.sleep(for: .milliseconds(20))
        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "同步收尾时写入",
            dueDate: nil,
            visibility: .shared
        )
        async let write = coordinator.trigger(.manual)

        let results = await (launch, write)
        XCTAssertEqual(results.0, .success)
        XCTAssertEqual(results.1, .success)
        XCTAssertEqual(try store.unsyncedCount(), 0)
        let exchangeCount = await transport.exchangeCount()
        XCTAssertEqual(exchangeCount, 3)
    }

    func testDeviceReuseRotatesInstallationIdentityAndRetriesUnchangedOutbox() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "更换设备标识后继续上传",
            dueDate: nil,
            visibility: .shared
        )
        let originalDeviceId = try store.deviceIdentifier()
        let pending = try await store.pendingOperations(limit: 1, now: .distantFuture)
        let originalOperation = try XCTUnwrap(pending.first)
        let transport = DeviceReusedOnceTransport()
        let coordinator = SyncCoordinator(store: store, transport: transport)

        let result = await coordinator.trigger(.manual)

        XCTAssertEqual(result, .success)
        XCTAssertNotEqual(try store.deviceIdentifier(), originalDeviceId)
        XCTAssertEqual(try store.unsyncedCount(), 0)
        let receivedOperationIds = await transport.operationIds()
        XCTAssertEqual(receivedOperationIds, [originalOperation.operationId])
    }

    func testIgnoredAckForcesAuthoritativeSnapshotBeforeFinishing() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = makeTodo(title: "初始")
        try store.bootstrap(notes: [], todos: [todo], anniversaries: [], calendarEvents: [])
        try store.editTodoTitle(id: todo.id, title: "本地较旧编辑")
        let transport = IgnoredGroupBootstrapTransport(todoId: todo.id)
        let coordinator = SyncCoordinator(store: store, transport: transport)

        let result = await coordinator.trigger(.manual)

        XCTAssertEqual(result, .success)
        let snapshot = try await store.loadSnapshot()
        let synchronized = try XCTUnwrap(snapshot.todos.first)
        XCTAssertEqual(synchronized.title, "服务器权威内容")
        XCTAssertEqual(try store.unsyncedCount(), 0)
        let exchangeCount = await transport.exchangeCount()
        XCTAssertEqual(exchangeCount, 2)
    }

    func testLiveConflictReconcilesSnapshotBeforeKeepingOperationForResolution() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "本地碰撞内容",
            dueDate: nil,
            visibility: .shared
        )
        let transport = LiveConflictTransport(todoId: local.id)
        let coordinator = SyncCoordinator(store: store, transport: transport)

        let result = await coordinator.trigger(.manual)

        XCTAssertEqual(result, .success)
        let snapshot = try await store.loadSnapshot()
        XCTAssertEqual(snapshot.todos.first?.title, "服务器已存在内容")
        XCTAssertEqual(try store.unsyncedCount(), 1)
        let resendable = try await store.pendingOperations(limit: 10, now: .distantFuture)
        XCTAssertTrue(resendable.isEmpty)
    }

    func testTwoDevicesConvergeByFieldGroupAndDeleteWins() async throws {
        let (storeA, rootA) = try makeStore()
        let (storeB, rootB) = try makeStore()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let initial = Todo(
            id: UUID().uuidString,
            coupleId: "couple",
            ownerId: "owner",
            title: "初始",
            note: nil,
            dueTime: nil,
            visibility: .shared,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: nil,
            createdAt: .now,
            updatedAt: .now
        )
        try storeA.bootstrap(notes: [], todos: [initial], anniversaries: [], calendarEvents: [])
        try storeB.bootstrap(notes: [], todos: [initial], anniversaries: [], calendarEvents: [])
        let server = ConvergingSyncTransport()
        let coordinatorA = SyncCoordinator(store: storeA, transport: server, retryBaseDelay: 0.01)
        let coordinatorB = SyncCoordinator(store: storeB, transport: server, retryBaseDelay: 0.01)

        try storeA.editTodoTitle(id: initial.id, title: "来自 A", now: .now.addingTimeInterval(1))
        _ = try storeB.toggleTodo(id: initial.id, completedBy: "owner", now: .now.addingTimeInterval(2))
        let firstA = await coordinatorA.trigger(.manual)
        let firstB = await coordinatorB.trigger(.manual)
        let secondA = await coordinatorA.trigger(.manual)
        XCTAssertEqual(firstA, .success)
        XCTAssertEqual(firstB, .success)
        XCTAssertEqual(secondA, .success)

        let snapshotA = try await storeA.loadSnapshot()
        let snapshotB = try await storeB.loadSnapshot()
        let a = try XCTUnwrap(snapshotA.todos.first)
        let b = try XCTUnwrap(snapshotB.todos.first)
        XCTAssertEqual(a.title, "来自 A")
        XCTAssertTrue(a.completed)
        XCTAssertEqual(a, b)

        try storeA.deleteTodo(id: initial.id, now: .now.addingTimeInterval(3))
        try storeB.editTodoTitle(id: initial.id, title: "删除后的晚到编辑", now: .now.addingTimeInterval(4))
        let deleteA = await coordinatorA.trigger(.manual)
        let deleteB = await coordinatorB.trigger(.manual)
        let deletePullA = await coordinatorA.trigger(.manual)
        XCTAssertEqual(deleteA, .success)
        XCTAssertEqual(deleteB, .success)
        XCTAssertEqual(deletePullA, .success)
        let deletedA = try await storeA.loadSnapshot()
        let deletedB = try await storeB.loadSnapshot()
        XCTAssertTrue(deletedA.todos.isEmpty)
        XCTAssertTrue(deletedB.todos.isEmpty)
    }

    func testAttachmentFileLifecycleKeepsFailureAndCleansAfterAck() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([1, 2, 3, 4])
        let note = try await store.createMemory(
            coupleId: "couple",
            ownerId: "owner",
            content: "有图记录",
            photos: [SelectedPhoto(
                data: bytes,
                filename: "offline.jpg",
                mimeType: "image/jpeg",
                width: 2,
                height: 2
            )],
            anniversaryId: nil,
            anniversaryTitle: nil,
            todoId: nil,
            todoTitle: nil,
            visibility: .shared
        )
        let record = try XCTUnwrap(store.pendingAttachmentRecords(for: note.id).first)
        let stagedBytes = try await store.pendingAttachment(relativePath: record.relativePath)
        XCTAssertEqual(stagedBytes, bytes)
        let pending = try await store.pendingOperations(limit: 1, now: .distantFuture)
        let operation = try XCTUnwrap(pending.first)

        try await store.fail(
            operationIds: [operation.operationId],
            message: "upload failed",
            now: .now,
            retryBaseDelay: 1
        )
        let retainedBytes = try await store.pendingAttachment(relativePath: record.relativePath)
        XCTAssertEqual(retainedBytes, bytes)

        let pendingRemoteAttachment = Attachment(
            id: UUID().uuidString,
            filename: record.filename,
            mimeType: record.mimeType,
            size: record.size,
            width: record.width,
            height: record.height,
            durationMs: nil,
            finalized: true,
            processingStatus: "pending",
            createdAt: .now,
            sortOrder: 0,
            url: nil,
            posterUrl: nil,
            demoAssetName: nil
        )
        try store.markAttachmentUploadPrepared(
            localId: record.localId,
            serverAttachmentId: pendingRemoteAttachment.id,
            objectKey: "uploads/kept-until-content-ack",
            presignedUploadURL: "https://upload.invalid/signed"
        )
        try store.markAttachmentFinalized(
            localId: record.localId,
            serverAttachment: pendingRemoteAttachment
        )
        let finalized = try XCTUnwrap(store.pendingAttachmentRecords(for: note.id).first)
        XCTAssertEqual(finalized.uploadObjectKey, "uploads/kept-until-content-ack")
        try store.markAttachmentsForReconciliation(parentIds: [note.id])
        let reconciled = try XCTUnwrap(store.pendingAttachmentRecords(for: note.id).first)
        XCTAssertEqual(reconciled.syncState, AttachmentSyncState.uploading.rawValue)
        XCTAssertEqual(reconciled.uploadObjectKey, "uploads/kept-until-content-ack")
        try store.markAttachmentFinalized(
            localId: record.localId,
            serverAttachment: pendingRemoteAttachment
        )
        try await store.acknowledge(operationIds: [operation.operationId], now: .now)
        let bytesAfterAck = try await store.pendingAttachment(relativePath: record.relativePath)
        XCTAssertEqual(bytesAfterAck, bytes)

        let readyClock = HybridLogicalTimestamp(
            wallTimeMilliseconds: Date.now.millisecondsSince1970,
            counter: 0,
            deviceId: "server"
        )
        try await store.applyRemotePage(
            PullPage(
                changes: [RemoteEntityChange(
                    entityType: .attachment,
                    entityId: pendingRemoteAttachment.id,
                    ownerId: "owner",
                    visibility: Visibility.private.rawValue,
                    kind: .upsert,
                    fields: [
                        "filename": .string(record.filename),
                        "mimeType": .string(record.mimeType),
                        "size": .integer(record.size),
                        "width": .integer(record.width ?? 0),
                        "height": .integer(record.height ?? 0),
                        "url": .string("/v1/api/attachments/\(pendingRemoteAttachment.id)/download"),
                    ],
                    attachments: [],
                    changedFieldGroups: ["metadata"],
                    fieldClocks: ["metadata": readyClock],
                    tombstone: nil,
                    updatedAt: readyClock.date
                )],
                nextCursor: "attachment-ready",
                hasMore: false,
                serverTime: readyClock.date
            ),
            now: readyClock.date
        )
        do {
            _ = try await store.pendingAttachment(relativePath: record.relativePath)
            XCTFail("pending file should be removed after a remote download URL is available")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
        let readySnapshot = try await store.loadSnapshot()
        let synchronized = try XCTUnwrap(readySnapshot.notes.first?.attachments.first)
        XCTAssertEqual(
            synchronized.url,
            "/v1/api/attachments/\(pendingRemoteAttachment.id)/download"
        )
    }

    func testRemoteAttachmentCacheSurvivesStoreRecreation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = Data([9, 8, 7, 6])
        let first = try AttachmentFileStore(rootDirectory: root)
        _ = try await first.cacheRemoteData(expected, attachmentId: "remote-attachment")

        let reopened = try AttachmentFileStore(rootDirectory: root)
        let cached = try await reopened.cachedRemoteData(attachmentId: "remote-attachment")
        XCTAssertEqual(cached, expected)
    }

    func testUnsyncedSignOutRequiresExplicitDecisionAndDoesNotDeleteLocalData() async throws {
        let (offline, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try offline.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "不能静默丢失",
            dueDate: nil,
            visibility: .shared
        )
        let store = AppStore(offlineStore: offline, syncTransport: ConvergingSyncTransport())
        XCTAssertEqual(store.signOutDisposition(), .requiresDecision(1))
        let didSignOut = await store.signOutIfSafe()
        let retainedSnapshot = try await offline.loadSnapshot()
        XCTAssertFalse(didSignOut)
        XCTAssertEqual(try offline.unsyncedCount(), 1)
        XCTAssertEqual(retainedSnapshot.todos.map(\.title), ["不能静默丢失"])
    }

    func testExplicitDiscardClearsOutboxAndPendingAttachment() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try await store.createMemory(
            coupleId: "couple",
            ownerId: "owner",
            content: "稍后丢弃",
            photos: [SelectedPhoto(
                data: Data([1, 3, 5]),
                filename: "discard.jpg",
                mimeType: "image/jpeg",
                width: 1,
                height: 1
            )],
            anniversaryId: nil,
            anniversaryTitle: nil,
            todoId: nil,
            todoTitle: nil,
            visibility: .shared
        )
        let record = try XCTUnwrap(store.pendingAttachmentRecords(for: note.id).first)

        try await store.discardPendingMutationsAndLocalData()

        let discardedSnapshot = try await store.loadSnapshot()
        XCTAssertEqual(try store.unsyncedCount(), 0)
        XCTAssertTrue(discardedSnapshot.notes.isEmpty)
        do {
            _ = try await store.pendingAttachment(relativePath: record.relativePath)
            XCTFail("explicit discard should remove pending attachment bytes")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
    }

    func testYearlyOccurrencesAreExpandedWithoutBeingPersisted() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sourceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 8, day: 11)))
        _ = try store.createCalendarEvent(
            coupleId: "couple",
            ownerId: "owner",
            title: "每年纪念",
            start: sourceDate,
            end: nil,
            allDay: true,
            yearly: true
        )
        let canonical = try await store.loadSnapshot().canonicalCalendarEvents
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2028, month: 1, day: 1)))
        let occurrences = CalendarOccurrenceExpander.expand(
            canonicalEvents: canonical,
            from: sourceDate,
            to: end,
            calendar: calendar
        )
        XCTAssertEqual(canonical.count, 1)
        XCTAssertEqual(occurrences.count, 3)
        XCTAssertTrue(occurrences.allSatisfy { $0.recurrenceSourceId == canonical[0].id })
    }

    func testYearlyOccurrencesMatchServerSourceYearLeapDayAndOverlapRules() throws {
        let timezone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let feb29 = CalendarEvent(
            id: "feb29",
            coupleId: "couple",
            ownerId: "owner",
            title: "闰日",
            description: nil,
            allDay: false,
            startTime: try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-02-29T17:00:00Z")),
            endTime: nil,
            timezone: timezone.identifier,
            yearly: true,
            visibility: .shared,
            reminderOffset: nil,
            createdAt: .now,
            updatedAt: .now
        )
        let beforeSource = CalendarOccurrenceExpander.expand(
            canonicalEvents: [feb29],
            from: try XCTUnwrap(ISO8601DateFormatter().date(from: "2023-01-01T00:00:00Z")),
            to: try XCTUnwrap(ISO8601DateFormatter().date(from: "2023-12-31T23:59:59Z"))
        )
        XCTAssertTrue(beforeSource.isEmpty)

        let nonLeap = CalendarOccurrenceExpander.expand(
            canonicalEvents: [feb29],
            from: try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")),
            to: try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-12-31T23:59:59Z"))
        )
        let occurrence = try XCTUnwrap(nonLeap.first)
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timezone
        let localDate = localCalendar.dateComponents([.year, .month, .day, .hour], from: occurrence.startTime)
        XCTAssertEqual(localDate.year, 2025)
        XCTAssertEqual(localDate.month, 2)
        XCTAssertEqual(localDate.day, 28)
        XCTAssertEqual(localDate.hour, 12)
        XCTAssertEqual(occurrence.occurrenceId, "feb29~2025")

        let overlapping = CalendarEvent(
            id: "new-year",
            coupleId: "couple",
            ownerId: "owner",
            title: "跨年旅行",
            description: nil,
            allDay: false,
            startTime: try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-12-31T12:00:00Z")),
            endTime: try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-02T12:00:00Z")),
            timezone: "UTC",
            yearly: true,
            visibility: .shared,
            reminderOffset: nil,
            createdAt: .now,
            updatedAt: .now
        )
        let overlapRange = CalendarOccurrenceExpander.expand(
            canonicalEvents: [overlapping],
            from: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")),
            to: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T23:59:59Z"))
        )
        XCTAssertEqual(overlapRange.map(\.occurrenceId), ["new-year~2025"])
    }

    private func makeStore() throws -> (OfflineStore, URL) {
        let root = temporaryDirectory()
        return (
            try OfflineStore.makeInMemory(attachmentRoot: root.appending(path: "attachments")),
            root
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CoupleOfflineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func remoteTodo(
        id: String,
        kind: RemoteChangeKind,
        fields: [String: MutationValue],
        groups: Set<String>,
        clock: HybridLogicalTimestamp
    ) -> RemoteEntityChange {
        RemoteEntityChange(
            entityType: .todo,
            entityId: id,
            ownerId: "owner",
            visibility: Visibility.shared.rawValue,
            kind: kind,
            fields: fields,
            attachments: [],
            changedFieldGroups: groups,
            fieldClocks: Dictionary(uniqueKeysWithValues: groups.map { ($0, clock) }),
            tombstone: kind == .delete ? clock : nil,
            updatedAt: clock.date
        )
    }

    private func makeTodo(title: String) -> Todo {
        Todo(
            id: UUID().uuidString,
            coupleId: "couple",
            ownerId: "owner",
            title: title,
            note: nil,
            dueTime: nil,
            visibility: .shared,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

private actor RejectingSyncTransport: SyncTransport {
    private var mutationCalls = 0

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        if !operations.isEmpty {
            mutationCalls += 1
            throw SyncTransportError.rejected("payload cannot be repaired automatically")
        }
        return SyncExchange(
            acknowledgedOperationIds: [],
            page: PullPage(
                changes: [],
                nextCursor: cursor ?? "cursor",
                hasMore: false,
                serverTime: .now
            )
        )
    }

    func mutationExchangeCount() -> Int { mutationCalls }
}

private actor DeviceReusedOnceTransport: SyncTransport {
    private var didRejectDevice = false
    private var receivedOperationIds: [String] = []

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        if !didRejectDevice {
            didRejectDevice = true
            throw SyncTransportError.deviceReused
        }
        receivedOperationIds.append(contentsOf: operations.map(\.operationId))
        return SyncExchange(
            acknowledgedOperationIds: Set(operations.map(\.operationId)),
            page: PullPage(
                changes: [],
                nextCursor: cursor ?? "new-device-cursor",
                hasMore: false,
                serverTime: .now,
                mode: cursor == nil ? .snapshot : .incremental
            )
        )
    }

    func operationIds() -> [String] { receivedOperationIds }
}

private actor IgnoredGroupBootstrapTransport: SyncTransport {
    let todoId: String
    private var calls = 0
    private var authoritativeClock: HybridLogicalTimestamp?

    init(todoId: String) {
        self.todoId = todoId
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        calls += 1
        if let operation = operations.first {
            authoritativeClock = operation.hlc
            return SyncExchange(
                acknowledgedOperationIds: [operation.operationId],
                page: PullPage(
                    changes: [],
                    nextCursor: "before-authoritative-bootstrap",
                    hasMore: false,
                    serverTime: .now
                ),
                requiresAuthoritativeBootstrap: true
            )
        }
        let clock = authoritativeClock ?? HybridLogicalTimestamp(
            wallTimeMilliseconds: Date.now.millisecondsSince1970,
            counter: 0,
            deviceId: "server"
        )
        return SyncExchange(
            acknowledgedOperationIds: [],
            page: PullPage(
                changes: [RemoteEntityChange(
                    entityType: .todo,
                    entityId: todoId,
                    ownerId: "owner",
                    visibility: Visibility.shared.rawValue,
                    kind: .upsert,
                    fields: ["title": .string("服务器权威内容")],
                    attachments: [],
                    changedFieldGroups: ["content"],
                    fieldClocks: ["content": clock],
                    tombstone: nil,
                    updatedAt: clock.date
                )],
                nextCursor: "authoritative-cursor",
                hasMore: false,
                serverTime: .now,
                mode: .snapshot
            )
        )
    }

    func exchangeCount() -> Int { calls }
}

private actor LiveConflictTransport: SyncTransport {
    let todoId: String
    private var rejected = false

    init(todoId: String) {
        self.todoId = todoId
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        if !operations.isEmpty, !rejected {
            rejected = true
            throw SyncTransportError.liveConflict
        }
        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: 1,
            counter: 0,
            deviceId: "server"
        )
        return SyncExchange(
            acknowledgedOperationIds: [],
            page: PullPage(
                changes: [RemoteEntityChange(
                    entityType: .todo,
                    entityId: todoId,
                    ownerId: "owner",
                    visibility: Visibility.shared.rawValue,
                    kind: .upsert,
                    fields: ["title": .string("服务器已存在内容")],
                    attachments: [],
                    changedFieldGroups: ["content"],
                    fieldClocks: ["content": clock],
                    tombstone: nil,
                    updatedAt: clock.date
                )],
                nextCursor: "after-conflict-bootstrap",
                hasMore: false,
                serverTime: .now,
                mode: .snapshot
            )
        )
    }
}

private actor ConvergingSyncTransport: SyncTransport {
    private var entities: [String: RemoteEntityChange] = [:]
    private var revision = 0

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        for operation in operations {
            let existing = entities[operation.entityId]
            if existing?.kind == .delete, operation.mutationKind != .restore { continue }
            if operation.mutationKind == .delete {
                entities[operation.entityId] = RemoteEntityChange(
                    entityType: operation.entityType,
                    entityId: operation.entityId,
                    ownerId: "owner",
                    visibility: Visibility.shared.rawValue,
                    kind: .delete,
                    fields: existing?.fields ?? [:],
                    attachments: [],
                    changedFieldGroups: ["lifecycle"],
                    fieldClocks: existing?.fieldClocks ?? [:],
                    tombstone: operation.hlc,
                    updatedAt: operation.hlc.date
                )
                revision += 1
                continue
            }
            var fields = existing?.fields ?? [:]
            var clocks = existing?.fieldClocks ?? [:]
            for group in operation.changedFieldGroups {
                guard clocks[group] == nil || clocks[group]! < operation.hlc else { continue }
                for (name, value) in operation.payload.fields {
                    if Self.field(name, belongsTo: group, entityType: operation.entityType) {
                        fields[name] = value
                    }
                }
                if operation.entityType == .todo,
                   group == "completion",
                   case .boolean(let completed)? = fields["completed"] {
                    fields["completedAt"] = completed ? .date(operation.hlc.date) : .null
                    fields["completedBy"] = completed ? .string("owner") : .null
                }
                clocks[group] = operation.hlc
            }
            entities[operation.entityId] = RemoteEntityChange(
                entityType: operation.entityType,
                entityId: operation.entityId,
                ownerId: "owner",
                visibility: fields["visibility"]?.stringValue ?? Visibility.shared.rawValue,
                kind: operation.mutationKind == .restore ? .restore : .upsert,
                fields: fields,
                attachments: [],
                changedFieldGroups: Set(clocks.keys),
                fieldClocks: clocks,
                tombstone: nil,
                updatedAt: operation.hlc.date
            )
            revision += 1
        }
        return SyncExchange(
            acknowledgedOperationIds: Set(operations.map(\.operationId)),
            page: PullPage(
                changes: Array(entities.values),
                nextCursor: String(revision),
                hasMore: false,
                serverTime: .now
            )
        )
    }

    private static func field(
        _ name: String,
        belongsTo group: String,
        entityType: SyncEntityType
    ) -> Bool {
        switch (entityType, group) {
        case (.todo, "content"): ["title", "note"].contains(name)
        case (.todo, "schedule"): ["dueTime", "reminderOffset"].contains(name)
        case (.todo, "visibility"): name == "visibility"
        case (.todo, "completion"): ["completed", "completedAt", "completedBy"].contains(name)
        default: true
        }
    }
}

private actor TombstoneConflictTransport: SyncTransport {
    let deletedId: String
    private var rejected = false

    init(deletedId: String) {
        self.deletedId = deletedId
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        if !operations.isEmpty, !rejected {
            rejected = true
            throw SyncTransportError.tombstoneConflict
        }
        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: Date.now.millisecondsSince1970,
            counter: 0,
            deviceId: "server"
        )
        return SyncExchange(
            acknowledgedOperationIds: Set(operations.map(\.operationId)),
            page: PullPage(
                changes: [RemoteEntityChange(
                    entityType: .todo,
                    entityId: deletedId,
                    ownerId: "owner",
                    visibility: Visibility.shared.rawValue,
                    kind: .delete,
                    fields: [:],
                    attachments: [],
                    changedFieldGroups: ["lifecycle"],
                    fieldClocks: [:],
                    tombstone: clock,
                    updatedAt: clock.date
                )],
                nextCursor: "after-delete",
                hasMore: false,
                serverTime: .now
            )
        )
    }
}

private actor SlowSyncTransport: SyncTransport {
    let delay: Duration
    private var calls = 0

    init(delay: Duration) {
        self.delay = delay
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        calls += 1
        try await Task.sleep(for: delay)
        return SyncExchange(
            acknowledgedOperationIds: Set(operations.map(\.operationId)),
            page: PullPage(
                changes: [],
                nextCursor: cursor ?? "cursor",
                hasMore: false,
                serverTime: .now
            )
        )
    }

    func exchangeCount() -> Int { calls }
}

private extension MutationValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

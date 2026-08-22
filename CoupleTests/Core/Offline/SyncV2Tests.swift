import Foundation
import SwiftData
import XCTest
@testable import Couple

@MainActor
final class SyncV2Tests: XCTestCase {
    func testWireOperationHasNoClientClock() throws {
        let operation = PendingOperation(
            operationId: UUID().uuidString.lowercased(),
            entityType: .todo,
            entityId: UUID().uuidString.lowercased(),
            mutationKind: .update,
            payload: LocalMutationPayload(fields: ["title": .string("V2")]),
            changedFieldGroups: ["content"],
            hlc: HybridLogicalTimestamp(
                wallTimeMilliseconds: 99,
                counter: 7,
                deviceId: "legacy-local-only"
            ),
            retryCount: 0,
            createdAt: .now
        )

        let data = try APIClient.encoder.encode(try SyncV2Operation(operation: operation))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertNil(object["clientHlc"])
        XCTAssertNil(object["hlc"])
        XCTAssertEqual(object["changedGroups"] as? [String], ["content"])
        XCTAssertEqual((object["data"] as? [String: Any])?["title"] as? String, "V2")
    }

    func testAckDoesNotOverwriteANewerOptimisticFieldGroupAndCursorIsAtomic() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: UUID().uuidString.lowercased(),
            ownerId: UUID().uuidString.lowercased(),
            title: "first local value",
            dueDate: nil,
            visibility: .shared
        )
        let repository = SyncRepositoryV2(modelContainer: store.container)
        let initialOperations = try await repository.pendingOperations(
            limit: 1,
            now: .distantFuture
        )
        let create = try XCTUnwrap(initialOperations.first)
        try await repository.markSending(operationIds: [create.operationId], now: .now)

        let editContext = ModelContext(store.container)
        editContext.autosaveEnabled = false
        let localTodo = try XCTUnwrap(
            try editContext.fetch(FetchDescriptor<LocalTodoEntity>())
                .first(where: { $0.id == todo.id })
        )
        localTodo.title = "newer local value"
        localTodo.isDirty = true
        let update = OutboxEntity(
            operationId: UUID().uuidString.lowercased(),
            entityType: SyncEntityType.todo.rawValue,
            entityId: todo.id,
            mutationKind: MutationKind.update.rawValue,
            payloadData: try propertyListData(
                LocalMutationPayload(fields: ["title": .string("newer local value")])
            ),
            changedFieldGroups: ["content"],
            hlcData: try propertyListData(HybridLogicalTimestamp(
                wallTimeMilliseconds: 100,
                counter: 0,
                deviceId: "legacy-local-only"
            )),
            createdAt: create.createdAt.addingTimeInterval(1),
            updatedAt: create.createdAt.addingTimeInterval(1)
        )
        editContext.insert(update)
        try editContext.save()

        let exchange = SyncV2Exchange(
            operationResults: [SyncV2OperationResult(
                operationId: create.operationId,
                status: .applied,
                sequence: "1",
                replayed: false,
                errorCode: nil,
                message: nil
            )],
            page: PullPage(
                changes: [remoteTodo(id: todo.id, title: "server value", sequence: 1)],
                nextCursor: "cursor-1",
                hasMore: false,
                serverTime: .now,
                mode: .incremental
            )
        )

        let summary = try await repository.apply(
            exchange,
            sentOperationIds: [create.operationId],
            now: .now
        )
        XCTAssertEqual(summary.appliedCount, 1)
        XCTAssertTrue(summary.hasPendingOperations)
        let committedCursor = try await repository.cursor()
        XCTAssertEqual(committedCursor, "cursor-1")

        let verificationContext = ModelContext(store.container)
        let savedTodo = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<LocalTodoEntity>()).first
        )
        XCTAssertEqual(savedTodo.title, "newer local value")
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<OutboxEntity>()).map(\.operationId),
            [update.operationId]
        )

        do {
            _ = try await repository.apply(
                SyncV2Exchange(
                    operationResults: [],
                    page: PullPage(
                        changes: [remoteTodo(id: todo.id, title: "must roll back", sequence: 2)],
                        nextCursor: "cursor-must-not-commit",
                        hasMore: false,
                        serverTime: .now,
                        mode: .incremental
                    )
                ),
                sentOperationIds: [update.operationId],
                now: .now
            )
            XCTFail("Mismatched operation results must reject the whole local transaction")
        } catch {
            let cursorAfterRollback = try await repository.cursor()
            XCTAssertEqual(cursorAfterRollback, "cursor-1")
        }
    }

    func testEditingRejectedOperationReplacesItWithFreshCompleteOperation() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "rejected",
            dueDate: nil,
            visibility: .shared
        )
        let repository = SyncRepositoryV2(modelContainer: store.container)
        let initialOperations = try await repository.pendingOperations(
            limit: 1,
            now: .distantFuture
        )
        let original = try XCTUnwrap(initialOperations.first)
        try await repository.markSending(operationIds: [original.operationId], now: .now)
        _ = try await repository.apply(
            SyncV2Exchange(
                operationResults: [SyncV2OperationResult(
                    operationId: original.operationId,
                    status: .rejected,
                    sequence: nil,
                    replayed: false,
                    errorCode: "VALIDATION_ERROR",
                    message: "rejected"
                )],
                page: PullPage(
                    changes: [],
                    nextCursor: "cursor-rejected",
                    hasMore: false,
                    serverTime: .now,
                    mode: .incremental
                )
            ),
            sentOperationIds: [original.operationId],
            now: .now
        )

        let editor = try OfflineStore(
            container: store.container,
            attachmentFiles: store.attachmentFiles
        )
        try editor.editTodoTitle(id: todo.id, title: "fixed")
        let replacementRepository = SyncRepositoryV2(modelContainer: store.container)
        let replacements = try await replacementRepository.pendingOperations(
            limit: 10,
            now: .distantFuture
        )
        let replacement = try XCTUnwrap(replacements.first)

        XCTAssertNotEqual(replacement.operationId, original.operationId)
        XCTAssertEqual(replacement.mutationKind, .create)
        XCTAssertEqual(replacement.payload.fields["title"], .string("fixed"))
        XCTAssertEqual(
            replacement.changedFieldGroups,
            ["content", "schedule", "visibility", "completion"]
        )
    }

    func testRestartedSnapshotDiscardsStaleSeenSetBeforePruning() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = Todo(
            id: UUID().uuidString.lowercased(),
            coupleId: "couple",
            ownerId: "owner",
            title: "no longer visible",
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
        try store.bootstrap(
            notes: [],
            todos: [todo],
            anniversaries: [],
            calendarEvents: []
        )
        let setupContext = ModelContext(store.container)
        let metadata: SyncMetadataEntity
        if let existing = try setupContext.fetch(FetchDescriptor<SyncMetadataEntity>()).first {
            metadata = existing
        } else {
            metadata = SyncMetadataEntity(scopeId: OfflineStore.activeScope)
            setupContext.insert(metadata)
        }
        metadata.cursor = "stale-partial-snapshot"
        metadata.bootstrapCompleted = false
        metadata.snapshotSeenData = try propertyListData(["todo:\(todo.id)"])
        try setupContext.save()

        let repository = SyncRepositoryV2(modelContainer: store.container)
        _ = try await repository.apply(
            SyncV2Exchange(
                operationResults: [],
                page: PullPage(
                    changes: [],
                    nextCursor: "fresh-incremental-cursor",
                    hasMore: false,
                    serverTime: .now,
                    mode: .snapshot
                ),
                snapshotReset: true
            ),
            sentOperationIds: [],
            now: .now
        )

        let verificationContext = ModelContext(store.container)
        let saved = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<LocalTodoEntity>()).first
        )
        XCTAssertTrue(saved.isTombstoned)
    }

    func testPushDuringActiveExchangeForcesASecondPull() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = SyncRepositoryV2(modelContainer: store.container)
        let transport = GatedSyncV2Transport()
        let engine = SyncEngineV2(repository: repository, transport: transport)
        try await engine.resume()

        let first = Task { await engine.trigger(.launch) }
        await transport.waitUntilFirstExchangeStarts()
        let pushed = Task { await engine.trigger(.push) }
        try await Task.sleep(for: .milliseconds(25))
        await transport.releaseFirstExchange()

        let firstResult = await first.value.result
        let pushedResult = await pushed.value.result
        let exchangeCount = await transport.exchangeCount()
        XCTAssertEqual(firstResult, .success)
        XCTAssertEqual(pushedResult, .success)
        XCTAssertEqual(exchangeCount, 2)
    }

    func testStopAndWaitJoinsActiveSyncBeforeReturning() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = SyncRepositoryV2(modelContainer: store.container)
        let transport = CancellationSyncV2Transport()
        let engine = SyncEngineV2(repository: repository, transport: transport)
        try await engine.resume()

        let run = Task { await engine.trigger(.manual) }
        await transport.waitUntilExchangeStarts()
        await engine.stopAndWait()

        let result = await run.value.result
        let state = await engine.state
        let cursor = try await repository.cursor()
        let observedCancellation = await transport.didObserveCancellation()
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(state, .idle)
        XCTAssertNil(cursor)
        XCTAssertTrue(observedCancellation)
    }

    func testAutomaticPullFailureWithoutOutboxDoesNotLeaveEngineSyncing() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = SyncRepositoryV2(modelContainer: store.container)
        let engine = SyncEngineV2(
            repository: repository,
            transport: FailingSyncV2Transport()
        )
        try await engine.resume()

        let summary = await engine.trigger(.poll)
        let state = await engine.state

        guard case .failed = summary.result else {
            return XCTFail("The transport error should be surfaced in the run summary")
        }
        XCTAssertEqual(state, .idle)
    }

    private func makeStore() throws -> (OfflineStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CoupleSyncV2Tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            try OfflineStore.makeInMemory(
                attachmentRoot: root.appending(path: "attachments", directoryHint: .isDirectory)
            ),
            root
        )
    }

    private func propertyListData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    private func remoteTodo(id: String, title: String, sequence: Int64) -> RemoteEntityChange {
        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: 1_800_000_000_000,
            counter: sequence,
            deviceId: "server-v2"
        )
        return RemoteEntityChange(
            entityType: .todo,
            entityId: id,
            ownerId: "owner",
            visibility: Visibility.shared.rawValue,
            kind: .upsert,
            fields: ["title": .string(title)],
            attachments: [],
            changedFieldGroups: ["content"],
            fieldClocks: ["content": clock],
            tombstone: nil,
            updatedAt: clock.date
        )
    }
}

private actor GatedSyncV2Transport: SyncV2Transporting {
    private var calls = 0
    private var firstGate: CheckedContinuation<Void, Never>?
    private var firstWaiters: [CheckedContinuation<Void, Never>] = []

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncV2Exchange {
        calls += 1
        if calls == 1 {
            for waiter in firstWaiters { waiter.resume() }
            firstWaiters.removeAll()
            await withCheckedContinuation { firstGate = $0 }
        }
        return SyncV2Exchange(
            operationResults: operations.map {
                SyncV2OperationResult(
                    operationId: $0.operationId,
                    status: .applied,
                    sequence: String(calls),
                    replayed: false,
                    errorCode: nil,
                    message: nil
                )
            },
            page: PullPage(
                changes: [],
                nextCursor: "cursor-\(calls)",
                hasMore: false,
                serverTime: .now,
                mode: cursor == nil ? .snapshot : .incremental
            )
        )
    }

    func waitUntilFirstExchangeStarts() async {
        if calls > 0 { return }
        await withCheckedContinuation { firstWaiters.append($0) }
    }

    func releaseFirstExchange() {
        firstGate?.resume()
        firstGate = nil
    }

    func exchangeCount() -> Int { calls }
}

private actor CancellationSyncV2Transport: SyncV2Transporting {
    private var started = false
    private var cancelled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncV2Exchange {
        started = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        do {
            try await Task.sleep(for: .seconds(3_600))
            throw SyncTransportError.rejected("unexpected completion")
        } catch is CancellationError {
            cancelled = true
            throw CancellationError()
        }
    }

    func waitUntilExchangeStarts() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func didObserveCancellation() -> Bool { cancelled }
}

private struct FailingSyncV2Transport: SyncV2Transporting {
    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncV2Exchange {
        throw APIError.server(status: 503, code: "SERVICE_UNAVAILABLE", message: "unavailable")
    }
}

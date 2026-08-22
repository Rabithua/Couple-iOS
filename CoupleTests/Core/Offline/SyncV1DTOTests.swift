import Foundation
import SwiftData
import Testing
import XCTest
@testable import Couple

final class SyncV1DTOTests: XCTestCase {
    func testTodoCompletionMutationOnlySendsCompleted() throws {
        let deviceId = UUID().uuidString
        let operation = PendingOperation(
            operationId: UUID().uuidString,
            entityType: .todo,
            entityId: UUID().uuidString,
            mutationKind: .update,
            payload: LocalMutationPayload(fields: ["completed": .boolean(true)]),
            changedFieldGroups: ["completion"],
            hlc: HybridLogicalTimestamp(
                wallTimeMilliseconds: 1_786_435_200_000,
                counter: 2,
                deviceId: deviceId
            ),
            retryCount: 0,
            createdAt: .now
        )
        let request = SyncV1Request(
            protocolVersion: 1,
            deviceId: deviceId,
            cursor: nil,
            limit: 100,
            mutations: [try SyncV1Mutation(operation: operation, deviceId: deviceId)]
        )
        let data = try APIClient.encoder.encode(request)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let mutation = try XCTUnwrap((root["mutations"] as? [[String: Any]])?.first)
        let payload = try XCTUnwrap(mutation["data"] as? [String: Any])
        let clientHlc = try XCTUnwrap(mutation["clientHlc"] as? [String: Any])

        XCTAssertEqual(Set(payload.keys), ["completed"])
        XCTAssertEqual(payload["completed"] as? Bool, true)
        XCTAssertNil(payload["completedAt"])
        XCTAssertNil(payload["completedBy"])
        XCTAssertEqual(clientHlc["wallTimeMs"] as? String, "1786435200000")
        XCTAssertNil(clientHlc["deviceId"])
    }

    func testDeleteOmitsDataAndUsesLifecycleOnly() throws {
        let deviceId = UUID().uuidString
        let operation = PendingOperation(
            operationId: UUID().uuidString,
            entityType: .memory,
            entityId: UUID().uuidString,
            mutationKind: .delete,
            payload: LocalMutationPayload(fields: [:]),
            changedFieldGroups: ["lifecycle"],
            hlc: HybridLogicalTimestamp(
                wallTimeMilliseconds: 10,
                counter: 0,
                deviceId: deviceId
            ),
            retryCount: 0,
            createdAt: .now
        )
        let mutation = try SyncV1Mutation(operation: operation, deviceId: deviceId)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: APIClient.encoder.encode(mutation)) as? [String: Any]
        )
        XCTAssertEqual(object["entityType"] as? String, "note")
        XCTAssertEqual(object["changedGroups"] as? [String], ["lifecycle"])
        XCTAssertNil(object["data"])
    }

    func testMemoryLocationMutationPreservesCoordinatePrecision() throws {
        let deviceId = UUID().uuidString
        let operation = PendingOperation(
            operationId: UUID().uuidString,
            entityType: .memory,
            entityId: UUID().uuidString,
            mutationKind: .update,
            payload: LocalMutationPayload(fields: [
                "latitude": .double(30.274_084_8),
                "longitude": .double(120.155_070_7),
                "locationName": .string("西湖"),
            ]),
            changedFieldGroups: ["location"],
            hlc: HybridLogicalTimestamp(
                wallTimeMilliseconds: 1_786_435_200_000,
                counter: 0,
                deviceId: deviceId
            ),
            retryCount: 0,
            createdAt: .now
        )

        let mutation = try SyncV1Mutation(operation: operation, deviceId: deviceId)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: APIClient.encoder.encode(mutation)) as? [String: Any]
        )
        let payload = try XCTUnwrap(object["data"] as? [String: Any])

        XCTAssertEqual(try XCTUnwrap(payload["latitude"] as? Double), 30.274_084_8, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(payload["longitude"] as? Double), 120.155_070_7, accuracy: 0.000_000_1)
        XCTAssertEqual(payload["locationName"] as? String, "西湖")
        XCTAssertEqual(object["changedGroups"] as? [String], ["location"])
    }

    func testMemorySnapshotDecodesCoordinatesAsDoubles() throws {
        let json = #"""
        {
          "serverTime":"2026-08-11T08:00:00.000Z",
          "authoritativeHlc":{"wallTimeMs":"1786435200000","counter":0,"deviceId":"server"},
          "revision":"1","mode":"snapshot","acks":[],
          "snapshot":[{
            "entityType":"note","entityId":"30000000-0000-4000-8000-000000000001",
            "ownerId":"40000000-0000-4000-8000-000000000001","visibility":"shared",
            "revision":"1","hlc":{"wallTimeMs":"1786435200000","counter":0,"deviceId":"server"},
            "fieldVersions":{"location":{"wallTimeMs":"1786435200000","counter":0,"deviceId":"server"}},
            "deleted":false,
            "data":{"latitude":30.2740848,"longitude":120.1550707,"locationName":"西湖"}
          }],
          "changes":[],"nextCursor":"1","hasMore":false
        }
        """#.data(using: .utf8)!

        let exchange = try APIClient.decoder.decode(SyncV1Response.self, from: json).exchange
        let fields = try XCTUnwrap(exchange.page.changes.first?.fields)
        XCTAssertEqual(fields["latitude"], .double(30.274_084_8))
        XCTAssertEqual(fields["longitude"], .double(120.155_070_7))
        XCTAssertEqual(fields["locationName"], .string("西湖"))
    }

    func testSnapshotFixtureDecodesOpaqueCursorAndCanonicalCalendarEvent() throws {
        let json = #"""
        {
          "serverTime": "2026-08-11T08:00:00.000Z",
          "authoritativeHlc": {"wallTimeMs":"1786435200000","counter":0,"deviceId":"server"},
          "revision": "4218",
          "mode": "snapshot",
          "acks": [],
          "snapshot": [{
            "entityType":"calendarEvent",
            "entityId":"30000000-0000-4000-8000-000000000002",
            "ownerId":"40000000-0000-4000-8000-000000000001",
            "visibility":"shared",
            "revision":"4198",
            "hlc":{"wallTimeMs":"1786300000000","counter":0,"deviceId":"server"},
            "fieldVersions":{
              "content":{"wallTimeMs":"1786300000000","counter":0,"deviceId":"server"},
              "schedule":{"wallTimeMs":"1786300000000","counter":0,"deviceId":"server"},
              "visibility":{"wallTimeMs":"1786300000000","counter":0,"deviceId":"server"}
            },
            "deleted":false,
            "data":{
              "title":"清迈旅行","description":null,"allDay":true,
              "startTime":"2026-10-01T00:00:00.000Z","endTime":"2026-10-07T00:00:00.000Z",
              "timezone":"Asia/Shanghai","yearly":false,"visibility":"shared","reminderOffset":1440
            }
          }],
          "changes":[],
          "nextCursor":"opaque-do-not-decode",
          "hasMore":false
        }
        """#.data(using: .utf8)!

        let decoded = try APIClient.decoder.decode(SyncV1Response.self, from: json)
        let exchange = try decoded.exchange
        XCTAssertEqual(exchange.page.nextCursor, "opaque-do-not-decode")
        XCTAssertEqual(exchange.page.mode, .snapshot)
        XCTAssertEqual(exchange.page.authoritativeClock?.wallTimeMilliseconds, 1_786_435_200_000)
        XCTAssertEqual(exchange.page.changes.first?.entityType, .calendarEvent)
        XCTAssertEqual(exchange.page.changes.first?.fields["title"], .string("清迈旅行"))
        XCTAssertNil(exchange.page.changes.first?.fields["occurrenceId"])
        XCTAssertNil(exchange.page.changes.first?.fields["recurrenceSourceId"])
    }

    func testIncrementalAckAndVisibilityRevocationDecodeFromFrozenShape() throws {
        let json = #"""
        {
          "serverTime":"2026-08-11T08:00:00.000Z",
          "authoritativeHlc":{"wallTimeMs":"1786435200000","counter":4,"deviceId":"server"},
          "revision":"4220","mode":"incremental",
          "acks":[{
            "operationId":"20000000-0000-4000-8000-000000000001","status":"superseded",
            "entityType":"todo","entityId":"30000000-0000-4000-8000-000000000001",
            "acceptedGroups":[],"ignoredGroups":["content"],"revision":"4219",
            "authoritativeHlc":{"wallTimeMs":"1786435100000","counter":0,"deviceId":"server"},
            "clockAdjusted":true
          }],
          "snapshot":[],
          "changes":[{
            "sequence":"4220","kind":"delete","changedGroups":["lifecycle"],
            "reason":"visibilityRevoked",
            "entity":{
              "entityType":"note","entityId":"30000000-0000-4000-8000-000000000009",
              "ownerId":"40000000-0000-4000-8000-000000000002","visibility":"private",
              "revision":"4220","hlc":{"wallTimeMs":"1786435190000","counter":0,"deviceId":"server"},
              "fieldVersions":{},"deleted":true,"data":null
            }
          }],
          "nextCursor":"opaque-incremental","hasMore":false
        }
        """#.data(using: .utf8)!

        let response = try APIClient.decoder.decode(SyncV1Response.self, from: json)
        let exchange = try response.exchange
        XCTAssertEqual(
            exchange.acknowledgedOperationIds,
            Set(["20000000-0000-4000-8000-000000000001"])
        )
        XCTAssertEqual(exchange.page.mode, .incremental)
        XCTAssertEqual(exchange.page.changes.first?.entityType, .memory)
        XCTAssertEqual(exchange.page.changes.first?.kind, .delete)
        XCTAssertEqual(exchange.page.changes.first?.reason, "visibilityRevoked")
        XCTAssertTrue(exchange.page.changes.first?.fields.isEmpty == true)
        XCTAssertTrue(exchange.requiresAuthoritativeBootstrap)
    }

    func testCreateRejectsIncompleteFieldGroupsBeforeNetwork() {
        let deviceId = UUID().uuidString
        let operation = PendingOperation(
            operationId: UUID().uuidString,
            entityType: .todo,
            entityId: UUID().uuidString,
            mutationKind: .create,
            payload: LocalMutationPayload(fields: ["title": .string("incomplete")]),
            changedFieldGroups: ["content"],
            hlc: HybridLogicalTimestamp(wallTimeMilliseconds: 1, counter: 0, deviceId: deviceId),
            retryCount: 0,
            createdAt: .now
        )
        XCTAssertThrowsError(try SyncV1Mutation(operation: operation, deviceId: deviceId))
    }

    func testLegacyPendingMemoryCreateWithoutLocationRemainsSendableAfterUpgrade() throws {
        let deviceId = UUID().uuidString
        let operation = PendingOperation(
            operationId: UUID().uuidString,
            entityType: .memory,
            entityId: UUID().uuidString,
            mutationKind: .create,
            payload: LocalMutationPayload(fields: [
                "content": .string("升级前待同步动态"),
                "anniversaryId": .null,
                "todoId": .null,
                "visibility": .string(Visibility.shared.rawValue),
                "attachmentIds": .strings([]),
            ]),
            changedFieldGroups: ["content", "associations", "visibility", "attachments"],
            hlc: HybridLogicalTimestamp(wallTimeMilliseconds: 1, counter: 0, deviceId: deviceId),
            retryCount: 0,
            createdAt: .now
        )

        XCTAssertNoThrow(try SyncV1Mutation(operation: operation, deviceId: deviceId))
    }
}

@Suite("Sync v1 timestamp contract")
@MainActor
struct SyncV1TimestampContractTests {
    @Test("PostgreSQL offset timestamps decode by field without changing ordinary strings")
    func offsetTimestampsDecodeByField() throws {
        let json = #"""
        {
          "serverTime":"2026-08-22T00:00:00.000Z",
          "authoritativeHlc":{"wallTimeMs":"1787356800000","counter":0,"deviceId":"server"},
          "revision":"91","mode":"snapshot","acks":[],
          "snapshot":[
            {
              "entityType":"calendarEvent","entityId":"30000000-0000-4000-8000-000000000001",
              "ownerId":"40000000-0000-4000-8000-000000000001","visibility":"shared",
              "revision":"88","hlc":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"},
              "fieldVersions":{"schedule":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"}},
              "deleted":false,
              "data":{"title":"吐槽小会","allDay":false,"startTime":"2026-08-29T07:00:00+00:00",
                "endTime":"2026-08-29T17:00:00+08:00","timezone":"Asia/Shanghai","yearly":false,
                "visibility":"shared","reminderEnabled":false}
            },
            {
              "entityType":"todo","entityId":"30000000-0000-4000-8000-000000000002",
              "ownerId":"40000000-0000-4000-8000-000000000001","visibility":"shared",
              "revision":"89","hlc":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"},
              "fieldVersions":{"schedule":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"}},
              "deleted":false,"data":{"title":"准备材料","dueTime":"2026-08-30T08:00:00+08:00","completedAt":null}
            },
            {
              "entityType":"anniversary","entityId":"30000000-0000-4000-8000-000000000003",
              "ownerId":"40000000-0000-4000-8000-000000000001","visibility":"shared",
              "revision":"90","hlc":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"},
              "fieldVersions":{"schedule":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"}},
              "deleted":false,"data":{"title":"纪念日","date":"2026-09-02","annual":true,
                "reminderInstant":"2026-09-01T09:30:00+08:00"}
            },
            {
              "entityType":"note","entityId":"30000000-0000-4000-8000-000000000004",
              "ownerId":"40000000-0000-4000-8000-000000000001","visibility":"shared",
              "revision":"91","hlc":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"},
              "fieldVersions":{"content":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"}},
              "deleted":false,"data":{"content":"2026-09-01T09:30:00+08:00"}
            }
          ],
          "changes":[],"nextCursor":"sequence-91","hasMore":false
        }
        """#.data(using: .utf8)!

        let response = try APIClient.decoder.decode(SyncV1Response.self, from: json)
        let changes = try response.exchange.page.changes
        let calendar = try #require(changes.first(where: { $0.entityType == .calendarEvent }))
        let todo = try #require(changes.first(where: { $0.entityType == .todo }))
        let anniversary = try #require(changes.first(where: { $0.entityType == .anniversary }))
        let note = try #require(changes.first(where: { $0.entityType == .memory }))

        #expect(calendar.fields["startTime"] == .date(try #require(
            APIISO8601Instant.parse("2026-08-29T07:00:00Z")
        )))
        #expect(calendar.fields["endTime"] == .date(try #require(
            APIISO8601Instant.parse("2026-08-29T09:00:00Z")
        )))
        #expect(todo.fields["dueTime"] == .date(try #require(
            APIISO8601Instant.parse("2026-08-30T00:00:00Z")
        )))
        #expect(todo.fields["completedAt"] == .null)
        #expect(anniversary.fields["date"] == .string("2026-09-02"))
        #expect(anniversary.fields["reminderInstant"] == .date(try #require(
            APIISO8601Instant.parse("2026-09-01T01:30:00Z")
        )))
        #expect(note.fields["content"] == .string("2026-09-01T09:30:00+08:00"))
    }

    @Test("An invalid required calendar timestamp rejects the response")
    func invalidCalendarTimestampRejectsResponse() throws {
        let json = #"""
        {
          "serverTime":"2026-08-22T00:00:00.000Z",
          "authoritativeHlc":{"wallTimeMs":"1787356800000","counter":0,"deviceId":"server"},
          "revision":"91","mode":"snapshot","acks":[],
          "snapshot":[{
            "entityType":"calendarEvent","entityId":"30000000-0000-4000-8000-000000000001",
            "ownerId":"40000000-0000-4000-8000-000000000001","visibility":"shared",
            "revision":"91","hlc":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"},
            "fieldVersions":{"schedule":{"wallTimeMs":"1787332909959","counter":0,"deviceId":"device"}},
            "deleted":false,"data":{"title":"吐槽小会","startTime":"not-an-instant"}
          }],
          "changes":[],"nextCursor":"sequence-91","hasMore":false
        }
        """#.data(using: .utf8)!

        let response = try APIClient.decoder.decode(SyncV1Response.self, from: json)
        #expect(throws: APIError.self) {
            _ = try response.exchange
        }
    }

    @Test("The timestamp contract migration forces a snapshot that repairs equal-clock data")
    func migrationRepairsEqualClockCalendarData() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appending(path: "CoupleOffline.store")
        let attachmentRoot = root.appending(path: "attachments", directoryHint: .isDirectory)
        let badStart = try #require(APIISO8601Instant.parse("2026-08-21T17:21:49.959Z"))
        let correctStart = try #require(APIISO8601Instant.parse("2026-08-29T07:00:00Z"))
        let eventID = "2736d556-5ab7-46d7-8deb-272d68268ef3"

        do {
            let oldStore = try OfflineStore.makePersistent(
                storeURL: storeURL,
                attachmentRoot: attachmentRoot
            )
            try oldStore.bootstrap(
                notes: [],
                todos: [],
                anniversaries: [],
                calendarEvents: [CalendarEvent(
                    id: eventID,
                    coupleId: "couple",
                    ownerId: "owner",
                    title: "吐槽小会",
                    description: nil,
                    allDay: false,
                    startTime: badStart,
                    endTime: nil,
                    timezone: "Asia/Shanghai",
                    yearly: false,
                    visibility: .shared,
                    reminderEnabled: false,
                    reminderOffset: nil,
                    createdAt: badStart,
                    updatedAt: badStart
                )],
                cursor: "sequence-91"
            )

            let context = ModelContext(oldStore.container)
            let marker = try #require(
                context.fetch(FetchDescriptor<SyncMetadataEntity>()).first(where: {
                    $0.scopeId == OfflineStore.timestampWireFormatMigrationScope
                })
            )
            context.delete(marker)
            try context.save()
        }

        let repairedStore = try OfflineStore.makePersistent(
            storeURL: storeURL,
            attachmentRoot: attachmentRoot
        )
        #expect(try await repairedStore.syncCursor() == nil)

        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: badStart.millisecondsSince1970,
            counter: 0,
            deviceId: "server"
        )
        try await repairedStore.applyRemotePage(
            PullPage(
                changes: [RemoteEntityChange(
                    entityType: .calendarEvent,
                    entityId: eventID,
                    ownerId: "owner",
                    visibility: Visibility.shared.rawValue,
                    kind: .upsert,
                    fields: [
                        "allDay": .boolean(false),
                        "startTime": .date(correctStart),
                        "endTime": .null,
                        "timezone": .string("Asia/Shanghai"),
                        "yearly": .boolean(false),
                        "reminderEnabled": .boolean(false),
                        "reminderOffset": .null,
                        "reminderLocalTime": .null,
                    ],
                    attachments: [],
                    changedFieldGroups: ["schedule"],
                    fieldClocks: ["schedule": clock],
                    tombstone: nil,
                    updatedAt: badStart
                )],
                nextCursor: "snapshot-complete",
                hasMore: false,
                serverTime: .now,
                mode: .snapshot
            ),
            now: .now
        )

        let snapshot = try await repairedStore.loadSnapshot()
        #expect(snapshot.canonicalCalendarEvents.first?.startTime == correctStart)
    }

    @Test("A malformed entity rolls back the complete remote page")
    func malformedEntityRollsBackCompletePage() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OfflineStore.makeInMemory(
            attachmentRoot: root.appending(path: "attachments", directoryHint: .isDirectory)
        )
        let todoID = UUID().uuidString
        let originalTime = Date(timeIntervalSince1970: 1_787_332_000)
        try store.bootstrap(
            notes: [],
            todos: [Todo(
                id: todoID,
                coupleId: "couple",
                ownerId: "owner",
                title: "原始内容",
                note: nil,
                dueTime: nil,
                visibility: .shared,
                completed: false,
                completedAt: nil,
                completedBy: nil,
                reminderOffset: nil,
                createdAt: originalTime,
                updatedAt: originalTime
            )],
            anniversaries: [],
            calendarEvents: []
        )
        let clock = HybridLogicalTimestamp(
            wallTimeMilliseconds: originalTime.millisecondsSince1970 + 1,
            counter: 0,
            deviceId: "server"
        )

        do {
            try await store.applyRemotePage(
                PullPage(
                    changes: [
                        RemoteEntityChange(
                            entityType: .todo,
                            entityId: todoID,
                            ownerId: "owner",
                            visibility: Visibility.shared.rawValue,
                            kind: .upsert,
                            fields: ["title": .string("不应被部分保存")],
                            attachments: [],
                            changedFieldGroups: ["content"],
                            fieldClocks: ["content": clock],
                            tombstone: nil,
                            updatedAt: clock.date
                        ),
                        RemoteEntityChange(
                            entityType: .calendarEvent,
                            entityId: UUID().uuidString,
                            ownerId: "owner",
                            visibility: Visibility.shared.rawValue,
                            kind: .upsert,
                            fields: ["title": .string("损坏事件")],
                            attachments: [],
                            changedFieldGroups: ["schedule"],
                            fieldClocks: ["schedule": clock],
                            tombstone: nil,
                            updatedAt: clock.date
                        ),
                    ],
                    nextCursor: "must-not-advance",
                    hasMore: false,
                    serverTime: .now
                ),
                now: .now
            )
            Issue.record("A page with an invalid calendar event unexpectedly succeeded")
        } catch {
            #expect(error is OfflineStoreError)
        }

        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.todos.first?.title == "原始内容")
        #expect(snapshot.canonicalCalendarEvents.isEmpty)
        #expect(try await store.syncCursor() == nil)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "SyncV1TimestampContractTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

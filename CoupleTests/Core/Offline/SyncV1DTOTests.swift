import Foundation
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
}

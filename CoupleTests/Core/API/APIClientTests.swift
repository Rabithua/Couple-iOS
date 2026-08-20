import Foundation
import Testing
@testable import Couple

extension Tag {
    @Tag static var networking: Self
}

struct APIClientTests {
    @Test("Concurrent refresh calls share one request", .tags(.networking))
    func concurrentRefreshCallsShareOneRequest() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(
            stubs: [
                .init(
                    pathSuffix: "/auth/refresh",
                    statusCode: 200,
                    data: Self.refreshSuccessData
                )
            ],
            blockedPathSuffixes: ["/auth/refresh"]
        )
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        let tasks = (0..<8).map { _ in
            Task { try await client.refreshSession() }
        }

        await session.waitForRequestCount(1)
        for _ in 0..<8 {
            await Task.yield()
        }
        await session.releaseRequests(matching: "/auth/refresh")

        var results: [Bool] = []
        for task in tasks {
            results.append(try await task.value)
        }

        #expect(results.allSatisfy { $0 })
        #expect(await session.requestCount(matching: "/auth/refresh") == 1)
        await client.clearSession()
    }

    @Test("Authorized attachment data retries once after 401", .tags(.networking))
    func authorizedDataRetriesOnceAfterUnauthorized() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(stubs: [
            .init(pathSuffix: "/attachments/1", statusCode: 401, data: Self.unauthorizedData),
            .init(pathSuffix: "/auth/refresh", statusCode: 200, data: Self.refreshSuccessData),
            .init(pathSuffix: "/attachments/1", statusCode: 401, data: Self.unauthorizedData)
        ])
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        let error = await #expect(throws: APIError.self) {
            try await client.authorizedData(at: "/attachments/1")
        }

        #expect(error == .server(
            status: 401,
            code: "UNAUTHORIZED",
            message: "unauthorized"
        ))
        #expect(await session.requestCount(matching: "/auth/refresh") == 1)
        #expect(await session.requestCount(matching: "/attachments/1") == 2)
        await client.clearSession()
    }

    @Test("Authorized root-relative resource does not duplicate the API path", .tags(.networking))
    func authorizedRootRelativeResourceUsesOrigin() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(stubs: [
            .init(
                pathSuffix: "/v1/api/attachments/1/download",
                statusCode: 200,
                data: Data("image-data".utf8)
            )
        ])
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        let data = try await client.authorizedData(at: "/v1/api/attachments/1/download")

        #expect(data == Data("image-data".utf8))
        #expect(await session.lastRequestedURL()?.absoluteString == "https://example.com/v1/api/attachments/1/download")
        await client.clearSession()
    }

    @Test("Transient refresh failure preserves the offline session", .tags(.networking))
    func transientRefreshFailurePreservesOfflineSession() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(stubs: [
            .init(
                pathSuffix: "/auth/refresh",
                statusCode: 503,
                data: Data(#"{"code":"UNAVAILABLE","message":"try later"}"#.utf8)
            )
        ])
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        let error = await #expect(throws: APIError.self) {
            try await client.refreshSession()
        }

        #expect(error == .server(status: 503, code: "UNAVAILABLE", message: "try later"))
        #expect(await client.hasStoredSession)
        await client.clearSession()
    }

    @Test("Profile updates use PATCH me with the new display name", .tags(.networking))
    func updateDisplayNameRequest() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(stubs: [
            .init(pathSuffix: "/me", statusCode: 200, data: Self.updatedUserData)
        ])
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        let user = try await client.updateMe(displayName: "New Name")

        #expect(user.displayName == "New Name")
        #expect(await session.lastHTTPMethod() == "PATCH")
        let body = try #require(await session.lastRequestBody())
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["displayName": "New Name"])
        await client.clearSession()
    }

    @Test("Leaving a couple uses the authenticated leave endpoint", .tags(.networking))
    func leaveCoupleRequest() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(stubs: [
            .init(pathSuffix: "/couples/leave", statusCode: 200, data: Self.emptySuccessData)
        ])
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        try await client.leaveCouple()

        #expect(await session.lastHTTPMethod() == "POST")
        #expect(await session.lastRequestedURL()?.path == "/v1/api/couples/leave")
        await client.clearSession()
    }

    @Test("Push device lifecycle uses PUT, PATCH, and DELETE", .tags(.networking))
    func pushDeviceLifecycleRequests() async throws {
        let baseURL = try #require(URL(string: "https://example.com/v1/api"))
        let keychain = KeychainStore(
            service: "couple-tests-\(UUID().uuidString)",
            persistenceEnabled: false
        )
        let session = MockHTTPSession(stubs: [
            .init(pathSuffix: "/push/devices/device-1", statusCode: 200, data: Self.pushDeviceData),
            .init(pathSuffix: "/push/devices/device-1", statusCode: 200, data: Self.pushDeviceData),
            .init(pathSuffix: "/push/devices/device-1", statusCode: 200, data: Self.emptySuccessData),
        ])
        let client = APIClient(baseURL: baseURL, session: session, keychain: keychain)
        try await client.install(tokens: Self.initialTokens)

        let registered = try await client.registerPushDevice(
            deviceId: "device-1",
            request: PushDeviceRegistrationRequest(
                token: "abcdef",
                environment: "sandbox",
                locale: "zh-Hans",
                appVersion: "1.0",
                appBuild: "1"
            )
        )
        #expect(registered.deviceId == "device-1")
        #expect(await session.lastHTTPMethod() == "PUT")

        _ = try await client.updatePushPreferences(
            deviceId: "device-1",
            request: PushPreferenceRequest(
                collaborationEnabled: false,
                remindersEnabled: true
            )
        )
        #expect(await session.lastHTTPMethod() == "PATCH")
        let body = try #require(await session.lastRequestBody())
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Bool])
        #expect(json == ["collaborationEnabled": false, "remindersEnabled": true])

        try await client.deletePushDevice(deviceId: "device-1")
        #expect(await session.lastHTTPMethod() == "DELETE")
        await client.clearSession()
    }

    private static let initialTokens = TokenPair(
        accessToken: "old-access",
        refreshToken: "old-refresh"
    )

    private static let refreshSuccessData = Data(#"""
    {
      "code": 0,
      "message": "success",
      "data": {
        "user": {
          "id": "user-1",
          "displayName": "Tester",
          "timezone": "Asia/Shanghai"
        },
        "tokens": {
          "accessToken": "new-access",
          "refreshToken": "new-refresh"
        }
      }
    }
    """#.utf8)

    private static let unauthorizedData = Data(#"""
    {
      "code": "UNAUTHORIZED",
      "message": "unauthorized"
    }
    """#.utf8)

    private static let updatedUserData = Data(#"""
    {
      "code": 0,
      "message": "success",
      "data": {
        "id": "user-1",
        "displayName": "New Name",
        "timezone": "Asia/Shanghai"
      }
    }
    """#.utf8)

    private static let emptySuccessData = Data(#"""
    {
      "code": 0,
      "message": "success",
      "data": null
    }
    """#.utf8)

    private static let pushDeviceData = Data(#"""
    {
      "code": 0,
      "message": "success",
      "data": {
        "deviceId": "device-1",
        "environment": "sandbox",
        "collaborationEnabled": true,
        "remindersEnabled": true,
        "active": true
      }
    }
    """#.utf8)
}

private actor MockHTTPSession: HTTPSession {
    struct Stub: Sendable {
        let pathSuffix: String
        let statusCode: Int
        let data: Data
    }

    enum MockError: Error {
        case missingStub(String)
    }

    private var stubs: [Stub]
    private var requests: [URLRequest] = []
    private var blockedPathSuffixes: Set<String>
    private var blockedRequests: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(stubs: [Stub], blockedPathSuffixes: Set<String> = []) {
        self.stubs = stubs
        self.blockedPathSuffixes = blockedPathSuffixes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        resumeSatisfiedRequestWaiters()

        let path = request.url?.path ?? ""
        if let suffix = blockedPathSuffixes.first(where: path.hasSuffix) {
            await withCheckedContinuation { continuation in
                blockedRequests[suffix, default: []].append(continuation)
            }
        }

        guard let stubIndex = stubs.firstIndex(where: { path.hasSuffix($0.pathSuffix) }) else {
            throw MockError.missingStub(path)
        }
        let stub = stubs.remove(at: stubIndex)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            throw APIError.invalidResponse
        }
        return (stub.data, response)
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }

    func requestCount(matching pathSuffix: String) -> Int {
        requests.count { $0.url?.path.hasSuffix(pathSuffix) == true }
    }

    func lastRequestedURL() -> URL? {
        requests.last?.url
    }

    func lastHTTPMethod() -> String? {
        requests.last?.httpMethod
    }

    func lastRequestBody() -> Data? {
        requests.last?.httpBody
    }

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func releaseRequests(matching pathSuffix: String) {
        blockedPathSuffixes.remove(pathSuffix)
        let continuations = blockedRequests.removeValue(forKey: pathSuffix) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func resumeSatisfiedRequestWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in requestWaiters {
            if requests.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        requestWaiters = remaining
    }
}

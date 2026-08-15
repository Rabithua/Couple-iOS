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

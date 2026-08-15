import Foundation

protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case server(status: Int, code: String, message: String)
    case decoding(String)
    case missingSession
    case uploadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无效响应"
        case .server(_, _, let message): message
        case .decoding(let detail): "数据解析失败：\(detail)"
        case .missingSession: "登录已过期，请重新登录"
        case .uploadFailed(let status): "照片上传失败（HTTP \(status)）"
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    let code: FlexibleCode
    let message: String
}

actor APIClient {
    static let productionBaseURL = URL(string: "https://oursince.com/v1/api")!

    let baseURL: URL
    private let session: any HTTPSession
    private let keychain: KeychainStore
    private var accessToken: String?
    private var refreshToken: String?
    private var refreshTask: Task<Bool, Error>?

    init(
        baseURL: URL = APIClient.productionBaseURL,
        session: any HTTPSession = URLSession.shared,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
        self.accessToken = keychain.value(for: .accessToken)
        self.refreshToken = keychain.value(for: .refreshToken)
    }

    var hasStoredSession: Bool { refreshToken != nil }

    func install(tokens: TokenPair) throws {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        try keychain.set(tokens.accessToken, for: .accessToken)
        try keychain.set(tokens.refreshToken, for: .refreshToken)
    }

    func clearSession() {
        accessToken = nil
        refreshToken = nil
        keychain.removeAll()
    }

    func request<Value: Decodable & Sendable>(
        _ path: String,
        method: HTTPMethod = .get,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Value {
        try await perform(
            path,
            method: method,
            query: query,
            body: nil,
            authenticated: authenticated,
            mayRefresh: true
        )
    }

    func request<Value: Decodable & Sendable, Body: Encodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        body: Body,
        authenticated: Bool = true
    ) async throws -> Value {
        let data = try Self.encoder.encode(body)
        return try await perform(
            path,
            method: method,
            query: query,
            body: data,
            authenticated: authenticated,
            mayRefresh: true
        )
    }

    func requestEmpty<Body: Encodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        body: Body,
        authenticated: Bool = true
    ) async throws {
        let data = try Self.encoder.encode(body)
        try await performEmpty(
            path,
            method: method,
            body: data,
            authenticated: authenticated,
            mayRefresh: true
        )
    }

    func requestEmpty(
        _ path: String,
        method: HTTPMethod,
        authenticated: Bool = true
    ) async throws {
        try await performEmpty(
            path,
            method: method,
            body: nil,
            authenticated: authenticated,
            mayRefresh: true
        )
    }

    func authorizedData(at path: String) async throws -> Data {
        try await authorizedData(at: path, mayRefresh: true)
    }

    private func authorizedData(at path: String, mayRefresh: Bool) async throws -> Data {
        var request = URLRequest(url: try makeResourceURL(path: path))
        request.setValue("Bearer \(try requireAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401, mayRefresh, try await refreshSession() {
            return try await authorizedData(at: path, mayRefresh: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw parseServerError(data: data, status: http.statusCode)
        }
        return data
    }

    func upload(_ data: Data, to presignedURL: URL, mimeType: String) async throws {
        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.uploadFailed(http.statusCode)
        }
    }

    @discardableResult
    func refreshSession() async throws -> Bool {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refreshToken else { return false }

        let task = Task {
            try await performRefresh(using: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }

    private func performRefresh(using refreshToken: String) async throws -> Bool {
        let body = try Self.encoder.encode(["refreshToken": refreshToken])
        let request = try makeRequest(
            path: "/auth/refresh",
            method: .post,
            query: [],
            body: body,
            authenticated: false
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if [400, 401, 403].contains(http.statusCode) {
                clearSession()
                return false
            }
            throw parseServerError(data: data, status: http.statusCode)
        }

        do {
            let envelope = try Self.decoder.decode(APIEnvelope<AuthResult>.self, from: data)
            guard envelope.code.isSuccess else {
                clearSession()
                return false
            }
            try install(tokens: envelope.data.tokens)
            return true
        } catch {
            clearSession()
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func perform<Value: Decodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        query: [URLQueryItem],
        body: Data?,
        authenticated: Bool,
        mayRefresh: Bool
    ) async throws -> Value {
        let request = try makeRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            authenticated: authenticated
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401, authenticated, mayRefresh, try await refreshSession() {
            return try await perform(
                path,
                method: method,
                query: query,
                body: body,
                authenticated: authenticated,
                mayRefresh: false
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw parseServerError(data: data, status: http.statusCode)
        }

        do {
            let envelope = try Self.decoder.decode(APIEnvelope<Value>.self, from: data)
            guard envelope.code.isSuccess else {
                throw APIError.server(status: http.statusCode, code: "API_ERROR", message: envelope.message)
            }
            return envelope.data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func performEmpty(
        _ path: String,
        method: HTTPMethod,
        body: Data?,
        authenticated: Bool,
        mayRefresh: Bool
    ) async throws {
        let request = try makeRequest(
            path: path,
            method: method,
            query: [],
            body: body,
            authenticated: authenticated
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401, authenticated, mayRefresh, try await refreshSession() {
            return try await performEmpty(
                path,
                method: method,
                body: body,
                authenticated: authenticated,
                mayRefresh: false
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw parseServerError(data: data, status: http.statusCode)
        }
        let envelope = try Self.decoder.decode(NullableAPIEnvelope<EmptyPayload>.self, from: data)
        guard envelope.code.isSuccess else {
            throw APIError.server(status: http.statusCode, code: "API_ERROR", message: envelope.message)
        }
    }

    private func makeRequest(
        path: String,
        method: HTTPMethod,
        query: [URLQueryItem],
        body: Data?,
        authenticated: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            request.setValue("Bearer \(try requireAccessToken())", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appending(path: normalized)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let result = components.url else { throw APIError.invalidResponse }
        return result
    }

    private func makeResourceURL(path: String) throws -> URL {
        guard path.hasPrefix("/"),
              let resourceComponents = URLComponents(string: path),
              var baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else {
            return try makeURL(path: path, query: [])
        }

        let basePath = baseComponents.path.hasSuffix("/")
            ? String(baseComponents.path.dropLast())
            : baseComponents.path
        guard resourceComponents.path == basePath
                || resourceComponents.path.hasPrefix("\(basePath)/")
        else {
            return try makeURL(path: path, query: [])
        }

        baseComponents.path = resourceComponents.path
        baseComponents.percentEncodedQuery = resourceComponents.percentEncodedQuery
        baseComponents.fragment = resourceComponents.fragment
        guard let result = baseComponents.url else { throw APIError.invalidResponse }
        return result
    }

    private func requireAccessToken() throws -> String {
        guard let accessToken else { throw APIError.missingSession }
        return accessToken
    }

    private func parseServerError(data: Data, status: Int) -> APIError {
        guard let envelope = try? Self.decoder.decode(APIErrorEnvelope.self, from: data) else {
            return .server(status: status, code: "HTTP_\(status)", message: HTTPURLResponse.localizedString(forStatusCode: status))
        }
        let code: String
        switch envelope.code {
        case .number(let value): code = String(value)
        case .text(let value): code = value
        }
        return .server(status: status, code: code, message: envelope.message)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let regular = ISO8601DateFormatter()
            regular.formatOptions = [.withInternetDateTime]
            for formatter in [fractional, regular] {
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unsupported ISO date: \(value)"
            )
        }
        return decoder
    }
}

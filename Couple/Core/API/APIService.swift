import Foundation

enum NoteQuery: Hashable, Sendable {
    case all
    case photos
    case anniversaries
    case completedTodos

    var items: [URLQueryItem] {
        var result = [URLQueryItem(name: "limit", value: "50")]
        switch self {
        case .all:
            break
        case .photos:
            result.append(URLQueryItem(name: "mediaType", value: "image"))
        case .anniversaries:
            result.append(URLQueryItem(name: "hasAnniversary", value: "true"))
        case .completedTodos:
            result.append(URLQueryItem(name: "hasTodo", value: "true"))
        }
        return result
    }
}

extension APIClient {
    func registrationOptions(displayName: String, timezone: String) async throws -> RegistrationOptionsResult {
        try await request(
            "/auth/passkey/register/options",
            method: .post,
            body: ["displayName": displayName, "timezone": timezone],
            authenticated: false
        )
    }

    func verifyRegistration(
        challengeKey: String,
        userId: String,
        credential: RegistrationCredentialResponse
    ) async throws -> AuthResult {
        let body = RegistrationVerificationRequest(
            challengeKey: challengeKey,
            userId: userId,
            response: credential
        )
        return try await request(
            "/auth/passkey/register/verify",
            method: .post,
            body: body,
            authenticated: false
        )
    }

    func authenticationOptions() async throws -> AuthenticationOptionsResult {
        try await request(
            "/auth/passkey/authenticate/options",
            method: .post,
            body: EmptyPayload(),
            authenticated: false
        )
    }

    func verifyAuthentication(
        challengeKey: String,
        credential: AuthenticationCredentialResponse
    ) async throws -> AuthResult {
        try await request(
            "/auth/passkey/authenticate/verify",
            method: .post,
            body: AuthenticationVerificationRequest(
                challengeKey: challengeKey,
                response: credential
            ),
            authenticated: false
        )
    }

    func me() async throws -> User { try await request("/me") }

    func relationshipStatus() async throws -> RelationshipStatus {
        try await request("/couples/status")
    }

    func createInvite() async throws -> InviteResult {
        try await request("/couples/invite", method: .post, body: EmptyPayload())
    }

    func acceptInvite(code: String) async throws -> AcceptInviteResult {
        try await request("/couples/accept", method: .post, body: ["code": code])
    }

    func updateCouple(startedOn: String, timezone: String) async throws -> Couple {
        try await request(
            "/couples",
            method: .patch,
            body: ["startedOn": startedOn, "timezone": timezone]
        )
    }

    func home() async throws -> HomeData { try await request("/home") }

    func notes(query: NoteQuery, cursor: String? = nil) async throws -> NotesPage {
        var items = query.items
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await request("/notes", query: items)
    }

    func createNote(_ request: CreateNoteRequest) async throws -> Note {
        try await self.request("/notes", method: .post, body: request)
    }

    func todos(filter: String = "all") async throws -> [Todo] {
        try await request("/todos", query: [URLQueryItem(name: "filter", value: filter)])
    }

    func createTodo(_ request: CreateTodoRequest) async throws -> Todo {
        try await self.request("/todos", method: .post, body: request)
    }

    func setTodo(_ id: String, completed: Bool) async throws -> Todo {
        let action = completed ? "complete" : "reopen"
        return try await request("/todos/\(id)/\(action)", method: .post, body: EmptyPayload())
    }

    func anniversaries() async throws -> [Anniversary] { try await request("/anniversaries") }

    func createAnniversary(_ request: CreateAnniversaryRequest) async throws -> Anniversary {
        try await self.request("/anniversaries", method: .post, body: request)
    }

    func calendar(from: Date, to: Date) async throws -> [CalendarEvent] {
        try await request(
            "/calendar",
            query: [
                URLQueryItem(name: "from", value: from.apiISOString),
                URLQueryItem(name: "to", value: to.apiISOString)
            ]
        )
    }

    func createCalendarEvent(_ request: CreateCalendarEventRequest) async throws -> CalendarEvent {
        try await self.request("/calendar", method: .post, body: request)
    }

    func requestUpload(_ request: PresignedUploadRequest) async throws -> PresignedUploadResult {
        try await self.request("/attachments/presigned", method: .post, body: request)
    }

    func finalizeUpload(objectKey: String) async throws -> Attachment {
        try await request(
            "/attachments/finalize",
            method: .post,
            body: ["objectKey": objectKey]
        )
    }

    func logOut() async {
        let token = refreshTokenForLogout
        if let token {
            try? await requestEmpty(
                "/auth/logout",
                method: .post,
                body: ["refreshToken": token]
            )
        }
        clearSession()
    }

    private var refreshTokenForLogout: String? {
        KeychainStore().value(for: .refreshToken)
    }
}

private struct RegistrationVerificationRequest: Encodable, Sendable {
    let challengeKey: String
    let userId: String
    let response: RegistrationCredentialResponse
}

private struct AuthenticationVerificationRequest: Encodable, Sendable {
    let challengeKey: String
    let response: AuthenticationCredentialResponse
}

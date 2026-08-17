import Foundation
import Testing
@testable import Couple

@MainActor
struct AppStoreTests {
    @Test("Past filters do not replace the home note collection")
    func pastFiltersDoNotReplaceHomeNotes() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()
        let homeNotes = store.notes

        await store.selectNotes(.photos)

        #expect(store.notes == homeNotes)
        #expect(store.pastNotes.count < homeNotes.count)
        #expect(store.pastNotes.allSatisfy { note in
            note.attachments.contains(where: \.isImage)
        })
    }

    @Test("Past page caches stay independent")
    func pastPageCachesStayIndependent() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()

        let photoNotes = store.pastNotes(for: .photos)
        await store.selectNotes(.completedTodos)

        #expect(!photoNotes.isEmpty)
        #expect(photoNotes.allSatisfy { $0.attachments.contains(where: \.isImage) })
        #expect(store.pastNotes.allSatisfy { $0.todoId != nil })
        #expect(store.pastNotes(for: .photos) == photoNotes)
    }

    @Test("Cached SwiftData content opens while refresh is offline")
    func cachedContentOpensBeforeNetworkRefresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AppStoreOfflineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        try offline.saveSession(
            user: SampleData.user,
            relationship: SampleData.relationship,
            home: SampleData.home
        )
        try offline.bootstrap(
            notes: SampleData.notes,
            todos: SampleData.todos,
            anniversaries: [SampleData.anniversary],
            calendarEvents: SampleData.events
        )
        let api = APIClient(
            baseURL: URL(string: "https://offline.invalid/v1/api")!,
            session: AlwaysOfflineHTTPSession(),
            keychain: KeychainStore(
                service: "couple-tests-\(UUID().uuidString)",
                persistenceEnabled: false
            )
        )
        try await api.install(tokens: TokenPair(accessToken: "access", refreshToken: "refresh"))
        let store = AppStore(
            api: api,
            offlineStore: offline,
            environment: [:],
            arguments: ["CoupleTests"]
        )

        await store.start()

        #expect(store.phase == .main)
        #expect(store.todos == SampleData.todos)
        #expect(Set(store.notes.map(\.id)) == Set(SampleData.notes.map(\.id)))
        await api.clearSession()
    }

    @Test("Changing the display name updates the current user and member list")
    func displayNameUpdatesDemoSession() async throws {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()

        try await store.updateDisplayName(" 新名字 ")

        #expect(store.currentUser?.displayName == "新名字")
        #expect(
            store.relationship?.members.first(where: { $0.id == SampleData.user.id })?.displayName
                == "新名字"
        )
    }

    @Test("Leaving a space keeps the signed-in user and returns to pairing")
    func leavingSpaceReturnsDemoSessionToPairing() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()

        let succeeded = await store.leaveSpaceIfSafe()

        #expect(succeeded)
        #expect(store.phase == .pairing)
        #expect(store.currentUser != nil)
        #expect(store.relationship?.couple == nil)
        #expect(store.todos.isEmpty)
        #expect(store.notes.isEmpty)
    }
}

private actor AlwaysOfflineHTTPSession: HTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

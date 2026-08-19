import Foundation
import Testing
@testable import Couple

@MainActor
struct AppStoreTests {
    @Test("Demo data never contains an empty note")
    func demoDataContainsNoEmptyNotes() {
        #expect(SampleData.notes.allSatisfy { $0.hasRecordContent })
    }

    @Test("A todo association cannot create an empty note")
    func todoAssociationCannotCreateEmptyNote() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()
        let originalNotes = store.notes

        do {
            try await store.addMemory(
                content: " \n ",
                photos: [],
                anniversaryId: nil,
                todoId: SampleData.todos[0].id,
                visibility: .shared
            )
            Issue.record("Expected empty note creation to fail")
        } catch Note.CreationError.empty {
            #expect(store.notes == originalNotes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Offline storage rejects an empty note before writing data")
    func offlineStorageRejectsEmptyNote() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "EmptyMemoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OfflineStore.makeInMemory(attachmentRoot: root)

        do {
            _ = try await store.createMemory(
                coupleId: "couple",
                ownerId: "owner",
                content: "\t",
                photos: [],
                anniversaryId: nil,
                anniversaryTitle: nil,
                todoId: "todo",
                todoTitle: "关联清单",
                visibility: .shared
            )
            Issue.record("Expected empty note creation to fail")
        } catch Note.CreationError.empty {
            let snapshot = try await store.loadSnapshot()
            #expect(snapshot.notes.isEmpty)
            #expect(
                try await store.pendingOperations(limit: 100, now: .distantFuture).isEmpty
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

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
        #expect(store.pastNotes.isEmpty)
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

    @Test("Changing the relationship date updates the complete demo session")
    func relationshipDateUpdatesDemoSession() async throws {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )
        await store.start()
        let calendar = Calendar.current
        let selectedDate = try #require(calendar.date(byAdding: .day, value: -12, to: .now))

        try await store.updateCouple(startedOn: selectedDate)

        let expectedDays = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: selectedDate),
            to: calendar.startOfDay(for: .now)
        ).day
        #expect(store.relationship?.couple?.startedOn == selectedDate.dateOnlyString)
        #expect(store.home?.daysTogether == expectedDays)
    }

    @Test("Interrupted space cleanup is completed before a session can open")
    func interruptedSpaceCleanupRecoversBeforeOpeningSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AppStoreCleanupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        _ = try offline.createTodo(
            coupleId: "old-couple",
            ownerId: "user",
            title: "不能带入新空间",
            dueDate: nil,
            visibility: .shared
        )
        let suiteName = "AppStoreCleanupTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(true, forKey: AppStore.pendingSpaceCleanupDefaultsKey)
        let baseURL = try #require(URL(string: "https://offline.invalid/v1/api"))
        let api = APIClient(
            baseURL: baseURL,
            session: AlwaysOfflineHTTPSession(),
            keychain: KeychainStore(
                service: "couple-tests-\(UUID().uuidString)",
                persistenceEnabled: false
            )
        )
        let store = AppStore(
            api: api,
            offlineStore: offline,
            userDefaults: userDefaults,
            environment: [:],
            arguments: ["CoupleTests"]
        )

        await store.start()

        let snapshot = try await offline.loadSnapshot()
        #expect(store.phase == .signedOut)
        #expect(snapshot.todos.isEmpty)
        #expect(try offline.unsyncedCount() == 0)
        #expect(userDefaults.object(forKey: AppStore.pendingSpaceCleanupDefaultsKey) == nil)
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

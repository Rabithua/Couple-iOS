import Foundation
import Testing
@testable import Couple

@MainActor
struct AppStoreTests {
    @Test("New Passkey registration continues through onboarding")
    func newRegistrationCompletesCreatePath() async throws {
        let store = AppStore(
            environment: [:],
            arguments: ["CoupleTests", "-ui-testing-demo", "-ui-testing-onboarding"]
        )
        await store.start()
        #expect(store.phase == .signedOut)

        await store.register()
        #expect(store.phase == .onboarding)
        #expect(store.currentUser?.onboardingCompleted == false)

        let birthday = try #require(
            Calendar.current.date(from: DateComponents(year: 2000, month: 8, day: 20))
        )
        await store.completeOnboarding(
            displayName: " 新用户 ",
            birthday: birthday,
            action: .create,
            inviteCode: nil
        )

        #expect(store.phase == .main)
        #expect(store.currentUser?.displayName == "新用户")
        #expect(store.currentUser?.onboardingCompleted == true)
        #expect(store.relationship?.members.count == 1)
        #expect(store.relationship?.pendingInvite != nil)
        #expect(store.anniversaries.count == 1)
        #expect(store.anniversaries.first?.systemKind == "birthday")
        #expect(store.anniversaries.first?.date == "2000-08-20")
    }

    @Test("Cached incomplete registration resumes at space selection")
    func cachedIncompleteOnboardingResumes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "OnboardingResumeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        var user = SampleData.user
        user.displayName = "oursince"
        user.onboardingCompleted = false
        let relationship = RelationshipStatus(couple: nil, members: [], pendingInvite: nil)
        try offline.saveSession(user: user, relationship: relationship, home: nil)
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

        #expect(store.phase == .onboarding)
        #expect(store.requiresOnboardingProfile)
        await api.clearSession()
    }

    @Test("A one-member existing space opens the home instead of pairing")
    func cachedOneMemberSpaceOpensHome() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "OneMemberSpaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        try offline.saveSession(
            user: SampleData.user,
            relationship: SampleData.unpairedRelationship,
            home: SampleData.unpairedHome
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
        #expect(store.relationship?.members.count == 1)
        await api.clearSession()
    }

    @Test("Demo data never contains an empty note")
    func demoDataContainsNoEmptyNotes() {
        #expect(SampleData.notes.allSatisfy { $0.hasRecordContent })
    }

    @Test("Anniversary icons match birthdays and a small set of occasion themes")
    func anniversaryIconsMatchOccasionThemes() {
        #expect(Anniversary.systemImageName(for: "我们的纪念日") == "party.popper.fill")
        #expect(Anniversary.systemImageName(for: "长野的生日") == "birthday.cake.fill")
        #expect(Anniversary.systemImageName(for: "结婚旅行") == "heart.circle.fill")
        #expect(Anniversary.systemImageName(for: "第一次见面") == "sparkles")
        #expect(Anniversary.systemImageName(for: "清迈旅行") == "airplane")
        #expect(Anniversary.systemImageName(for: "小狗到家") == "pawprint.fill")
        #expect(Anniversary.systemImageName(for: "搬进新家") == "house.fill")
        #expect(Anniversary.systemImageName(for: "毕业快乐") == "graduationcap.fill")
        #expect(Anniversary.systemImageName(for: "第一次吃火锅") == "fork.knife")

        var systemBirthday = SampleData.anniversary
        systemBirthday.title = "程袭"
        systemBirthday.systemKind = "birthday"
        #expect(systemBirthday.systemImageName == "birthday.cake.fill")
    }

    @Test("Exiting an in-app preview restores cached account data")
    func previewSessionRestoresCachedAccount() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PreviewSessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        try offline.saveSession(
            user: SampleData.user,
            relationship: SampleData.relationship,
            home: SampleData.unpairedHome
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
        #expect(store.home?.daysTogether == 0)
        #expect(store.notes.isEmpty)

        await store.enterPreview()
        #expect(store.isDemo)
        #expect(store.isPreviewSession)
        #expect(store.home?.daysTogether == SampleData.home.daysTogether)
        #expect(!store.notes.isEmpty)

        await store.exitPreview()
        #expect(!store.isDemo)
        #expect(!store.isPreviewSession)
        #expect(store.phase == .main)
        #expect(store.home?.daysTogether == 0)
        #expect(store.notes.isEmpty)
        #expect(await api.hasStoredSession)
        await api.clearSession()
    }

    @Test("Unpaired home demo exposes its invite and empty content")
    func unpairedHomeDemoState() async {
        let store = AppStore(
            environment: [:],
            arguments: ["CoupleTests", "-ui-testing-demo", "-ui-testing-unpaired"]
        )

        await store.start()

        #expect(store.phase == .main)
        #expect(store.relationship?.members.count == 1)
        #expect(store.relationship?.pendingInvite == SampleData.pendingInvite)
        #expect(store.notes.isEmpty)
        #expect(store.todos.isEmpty)
        #expect(store.anniversaries.isEmpty)
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

    @Test("Refreshing shared content also receives a partner's relationship date change")
    func refreshContentUpdatesRelationshipSummary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RelationshipRefreshTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        let staleRelationship = SampleData.relationship
        let staleHome = SampleData.home
        try offline.saveSession(
            user: SampleData.user,
            relationship: staleRelationship,
            home: staleHome
        )

        var refreshedCouple = try #require(staleRelationship.couple)
        refreshedCouple.startedOn = "2026-08-01"
        let refreshedRelationship = RelationshipStatus(
            couple: refreshedCouple,
            members: staleRelationship.members,
            pendingInvite: staleRelationship.pendingInvite
        )
        let refreshedHome = HomeData(
            daysTogether: 21,
            nextAnniversary: staleHome.nextAnniversary,
            nextUpcoming: staleHome.nextUpcoming,
            latestTimelineEntry: staleHome.latestTimelineEntry
        )
        let session = RelationshipRefreshHTTPSession(
            relationship: refreshedRelationship,
            home: refreshedHome
        )
        let api = APIClient(
            baseURL: URL(string: "https://example.com/v1/api")!,
            session: session,
            keychain: KeychainStore(
                service: "couple-tests-\(UUID().uuidString)",
                persistenceEnabled: false
            )
        )
        try await api.install(tokens: TokenPair(accessToken: "access", refreshToken: "refresh"))
        let store = AppStore(
            api: api,
            offlineStore: offline,
            syncTransport: EmptySyncTransport(),
            environment: [:],
            arguments: ["CoupleTests"]
        )
        store.currentUser = SampleData.user
        store.relationship = staleRelationship
        store.home = staleHome
        store.phase = .main

        await store.refreshContent()

        #expect(store.relationship?.couple?.startedOn == "2026-08-01")
        #expect(store.home?.daysTogether == 21)
        let cached = try #require(try offline.cachedSession())
        #expect(cached.relationship.couple?.startedOn == "2026-08-01")
        #expect(cached.home?.daysTogether == 21)
        #expect(await session.requestCount(for: "/v1/api/couples/status") == 1)
        #expect(await session.requestCount(for: "/v1/api/home") == 1)
        await api.clearSession()
    }

    @Test("Foreground polling removes a calendar event deleted by the partner")
    func foregroundPollReloadsPartnerCalendarDeletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ForegroundPollTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let offline = try OfflineStore.makeInMemory(attachmentRoot: root)
        let event = try #require(SampleData.events.first)
        try offline.bootstrap(
            notes: [],
            todos: [],
            anniversaries: [],
            calendarEvents: [event]
        )
        let transport = PartnerCalendarDeletionTransport(event: event)
        let store = AppStore(
            offlineStore: offline,
            syncV2Transport: transport,
            environment: [:],
            arguments: ["CoupleTests"]
        )
        store.currentUser = SampleData.user
        store.relationship = SampleData.relationship
        store.calendarEvents = [event]
        store.phase = .main

        let result = await store.synchronizeFromForegroundPoll()

        #expect(result == .success)
        #expect(store.calendarEvents.contains(where: { $0.id == event.id }) == false)
        let snapshot = try await offline.loadSnapshot()
        #expect(snapshot.canonicalCalendarEvents.contains(where: { $0.id == event.id }) == false)
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

private actor EmptySyncTransport: SyncTransport {
    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncExchange {
        SyncExchange(
            acknowledgedOperationIds: Set(operations.map(\.operationId)),
            page: PullPage(
                changes: [],
                nextCursor: cursor,
                hasMore: false,
                serverTime: .now
            )
        )
    }
}

private actor PartnerCalendarDeletionTransport: SyncV2Transporting {
    private let event: CalendarEvent

    init(event: CalendarEvent) {
        self.event = event
    }

    func exchange(
        cursor: String?,
        operations: [PendingOperation],
        limit: Int
    ) async throws -> SyncV2Exchange {
        let tombstone = HybridLogicalTimestamp(
            wallTimeMilliseconds: event.updatedAt.millisecondsSince1970 + 1,
            counter: 0,
            deviceId: "partner-device"
        )
        return SyncV2Exchange(
            operationResults: [],
            page: PullPage(
                changes: [RemoteEntityChange(
                    entityType: .calendarEvent,
                    entityId: event.id,
                    ownerId: event.ownerId,
                    visibility: event.visibility.rawValue,
                    kind: .delete,
                    fields: [:],
                    attachments: [],
                    changedFieldGroups: ["lifecycle"],
                    fieldClocks: [:],
                    tombstone: tombstone,
                    updatedAt: tombstone.date
                )],
                nextCursor: "partner-delete",
                hasMore: false,
                serverTime: tombstone.date
            )
        )
    }
}

private actor RelationshipRefreshHTTPSession: HTTPSession {
    private let responses: [String: Data]
    private var requestCounts: [String: Int] = [:]

    init(relationship: RelationshipStatus, home: HomeData) {
        responses = [
            "/v1/api/couples/status": Self.envelope(relationship),
            "/v1/api/home": Self.envelope(home),
        ]
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
              let data = responses[url.path],
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            throw APIError.invalidResponse
        }
        requestCounts[url.path, default: 0] += 1
        return (data, response)
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }

    func requestCount(for path: String) -> Int {
        requestCounts[path, default: 0]
    }

    private static func envelope<Value: Encodable>(_ value: Value) -> Data {
        let data = try? JSONSerialization.data(withJSONObject: [
            "code": 0,
            "message": "ok",
            "data": JSONSerialization.jsonObject(with: APIClient.encoder.encode(value)),
        ])
        return data ?? Data()
    }
}

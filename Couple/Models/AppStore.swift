import AuthenticationServices
import Foundation
import Observation
import UIKit

enum SessionPhase: Equatable, Sendable {
    case launching
    case signedOut
    case pairing
    case main
}

struct SelectedPhoto: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let filename: String
    let mimeType: String
    let width: Int
    let height: Int
}

enum SignOutDisposition: Equatable, Sendable {
    case ready
    case requiresDecision(Int)
}

@MainActor
@Observable
final class AppStore {
    static let pendingSpaceCleanupDefaultsKey = "app.space.pendingLocalCleanup"

    let api: APIClient
    private let passkeys: PasskeyService
    private let userDefaults: UserDefaults
    private(set) var offlineStore: OfflineStore?
    private var syncCoordinator: SyncCoordinator?
    private var connectivityMonitor: ConnectivityMonitor?
    private var connectivityTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var localStoreInitializationError: Error?

    var phase: SessionPhase = .launching
    var currentUser: User?
    var relationship: RelationshipStatus?
    var home: HomeData?
    var notes: [Note] = []
    var pastNotes: [Note] = []
    private var cachedPastNotes: [NoteQuery: [Note]] = [:]
    var todos: [Todo] = [] {
        didSet { rebuildCalendarScheduleIndex() }
    }
    var anniversaries: [Anniversary] = []
    var calendarEvents: [CalendarEvent] = [] {
        didSet { rebuildCalendarScheduleIndex() }
    }
    private(set) var calendarScheduleIndex = CalendarScheduleIndex()
    var selectedNoteQuery: NoteQuery = .all
    var isBusy = false
    var isRefreshing = false
    var isSyncing = false
    var errorMessage: String?
    private(set) var pendingTodoIDs: Set<String> = []
    private(set) var isDemo: Bool

    var homeAnniversary: Anniversary? {
        guard let cached = home?.nextAnniversary else {
            return anniversaries.nextUpcomingAnniversary()
        }
        return anniversaries.first {
            $0.id.caseInsensitiveCompare(cached.id) == .orderedSame
        } ?? cached
    }

    private func rebuildCalendarScheduleIndex() {
        let nextIndex = CalendarScheduleIndex(events: calendarEvents, todos: todos)
        guard nextIndex != calendarScheduleIndex else { return }
        calendarScheduleIndex = nextIndex
    }

    init(
        api: APIClient = APIClient(),
        passkeys: PasskeyService = PasskeyService(),
        offlineStore suppliedOfflineStore: OfflineStore? = nil,
        syncTransport suppliedSyncTransport: (any SyncTransport)? = nil,
        userDefaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.api = api
        self.passkeys = passkeys
        self.userDefaults = userDefaults
        let demo = environment["COUPLE_DEMO_MODE"] == "1" || arguments.contains("-ui-testing-demo")
        self.isDemo = demo

        guard !demo else { return }
        do {
            let local = try suppliedOfflineStore ?? OfflineStore.makeLive()
            offlineStore = local
            syncCoordinator = SyncCoordinator(
                store: local,
                transport: suppliedSyncTransport ?? SyncV1Transport(api: api, store: local)
            )
        } catch {
            localStoreInitializationError = error
        }
    }

    func start() async {
        if isDemo {
            loadSampleData()
            phase = .main
            return
        }
        guard localStoreInitializationError == nil, let offlineStore else {
            errorMessage = localStoreInitializationError?.localizedDescription
                ?? AppLocalization.string("本地数据库无法打开")
            phase = .signedOut
            return
        }
        guard await recoverPendingSpaceCleanup() else {
            phase = .signedOut
            return
        }

        let hasStoredSession = await api.hasStoredSession
        guard hasStoredSession else {
            phase = .signedOut
            return
        }

        if let cached = try? offlineStore.cachedSession() {
            currentUser = cached.user
            relationship = cached.relationship
            home = cached.home
            if cached.relationship.members.count >= 2 {
                try? await loadLocalContent()
                phase = .main
            } else {
                phase = .pairing
            }
        }

        do {
            guard try await api.refreshSession() else {
                phase = .signedOut
                return
            }
            let user = try await api.me()
            let relationship = try await api.relationshipStatus()
            try await finishAuthentication(user: user, relationship: relationship, trigger: .launch)
        } catch is CancellationError {
            return
        } catch {
            if phase == .main {
                scheduleRetry()
            } else {
                errorMessage = error.localizedDescription
                phase = .signedOut
            }
        }
    }

    func enterPreview() {
        isDemo = true
        loadSampleData()
        phase = .main
    }

    func register(displayName: String) async {
        guard await recoverPendingSpaceCleanup() else { return }
        await runBusy {
            let timezone = TimeZone.current.identifier
            let result = try await api.registrationOptions(displayName: displayName, timezone: timezone)
            let credential = try await passkeys.register(options: result.options)
            let auth = try await api.verifyRegistration(
                challengeKey: result.challengeKey,
                userId: result.userId,
                credential: credential
            )
            try await api.install(tokens: auth.tokens)
            let relationship = try await api.relationshipStatus()
            try await finishAuthentication(user: auth.user, relationship: relationship, trigger: .login)
        }
    }

    func signIn() async {
        guard await recoverPendingSpaceCleanup() else { return }
        await runBusy {
            let result = try await api.authenticationOptions()
            let credential = try await passkeys.authenticate(options: result.options)
            let auth = try await api.verifyAuthentication(
                challengeKey: result.challengeKey,
                credential: credential
            )
            try await api.install(tokens: auth.tokens)
            let relationship = try await api.relationshipStatus()
            try await finishAuthentication(user: auth.user, relationship: relationship, trigger: .login)
        }
    }

    func createInvite() async {
        await runBusy {
            _ = try await api.createInvite()
            relationship = try await api.relationshipStatus()
            try persistSession()
        }
    }

    func acceptInvite(_ code: String) async {
        await runBusy {
            _ = try await api.acceptInvite(code: code.uppercased())
            let status = try await api.relationshipStatus()
            guard let currentUser else { throw APIError.missingSession }
            try await finishAuthentication(user: currentUser, relationship: status, trigger: .login)
        }
    }

    func continueWithoutPartner() async {
        phase = .main
        try? persistSession()
        beginConnectivityObservation()
        await refreshContent()
    }

    func refreshContent() async {
        guard !isDemo else {
            loadSampleData(keepingTodoState: true)
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await loadLocalContent()
            let result = await synchronize(trigger: .manual, surfaceError: false)
            if case .failed = result, try await localDomainIsEmpty() {
                try await bootstrapFromLegacyAPI()
                try await loadLocalContent()
            }
            do {
                home = try await api.home()
                if let home { try offlineStore?.updateCachedHome(home) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if case .failed = result { throw error }
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleForeground() {
        guard phase == .main, !isDemo else { return }
        Task { _ = await synchronize(trigger: .foreground, surfaceError: false) }
    }

    func pastNotes(for query: NoteQuery) -> [Note] {
        cachedPastNotes[query] ?? notes.filter { matches($0, query: query) }
    }

    func selectNotes(_ query: NoteQuery, forceReload: Bool = false) async {
        selectedNoteQuery = query
        if forceReload { await refreshContent() }
        let filtered = notes.filter { matches($0, query: query) }
        cachedPastNotes[query] = filtered
        pastNotes = filtered
    }

    func toggleTodo(_ todo: Todo) async {
        _ = await setTodoCompletion(todo, completed: !todo.completed)
    }

    @discardableResult
    func setTodoCompletion(_ todo: Todo, completed: Bool) async -> Bool {
        guard pendingTodoIDs.insert(todo.id).inserted else { return false }
        defer { pendingTodoIDs.remove(todo.id) }
        if isDemo {
            guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return false }
            todos[index].completed = completed
            todos[index].completedAt = completed ? .now : nil
            todos[index].completedBy = completed ? currentUser?.id : nil
            return true
        }
        do {
            guard let offlineStore else { return false }
            _ = try offlineStore.setTodoCompletion(
                id: todo.id,
                completed: completed,
                completedBy: currentUser?.id
            )
            try await loadLocalContent()
            triggerSyncAfterWrite()
            return todos.first(where: { $0.id == todo.id })?.completed == completed
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addTodo(title: String, dueDate: Date?, visibility: Visibility) async throws {
        if isDemo {
            let todo = Todo(
                id: UUID().uuidString,
                coupleId: SampleData.relationship.couple!.id,
                ownerId: SampleData.user.id,
                title: title,
                note: nil,
                dueTime: dueDate,
                visibility: visibility,
                completed: false,
                completedAt: nil,
                completedBy: nil,
                reminderOffset: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            todos.insert(todo, at: 0)
            return
        }
        let identity = try localIdentity()
        _ = try offlineStore?.createTodo(
            coupleId: identity.coupleId,
            ownerId: identity.userId,
            title: title,
            dueDate: dueDate,
            visibility: visibility
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func updateTodo(
        _ todo: Todo,
        title: String,
        dueDate: Date?,
        visibility: Visibility
    ) async throws {
        if isDemo {
            guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
            todos[index].title = title
            todos[index].dueTime = dueDate
            todos[index].visibility = visibility
            todos[index].updatedAt = .now
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.editTodo(
            id: todo.id,
            title: title,
            dueDate: dueDate,
            visibility: visibility
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func deleteTodo(_ todo: Todo) async throws {
        if isDemo {
            todos.removeAll { $0.id == todo.id }
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.deleteTodo(id: todo.id)
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func addAnniversary(title: String, date: Date, annual: Bool, visibility: Visibility) async throws {
        if isDemo {
            var item = SampleData.anniversary
            item.title = title
            item.date = date.dateOnlyString
            item.annual = annual
            item.visibility = visibility
            anniversaries.append(item)
            return
        }
        let identity = try localIdentity()
        _ = try offlineStore?.createAnniversary(
            coupleId: identity.coupleId,
            ownerId: identity.userId,
            title: title,
            date: date,
            annual: annual,
            visibility: visibility
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func updateAnniversary(
        _ anniversary: Anniversary,
        title: String,
        date: Date,
        annual: Bool,
        visibility: Visibility
    ) async throws {
        if isDemo {
            guard let index = anniversaries.firstIndex(where: {
                $0.id.caseInsensitiveCompare(anniversary.id) == .orderedSame
            }) else { return }
            anniversaries[index].title = title
            anniversaries[index].date = date.dateOnlyString
            anniversaries[index].annual = annual
            anniversaries[index].nextOccurrence = nil
            anniversaries[index].visibility = visibility
            anniversaries[index].updatedAt = .now
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.editAnniversary(
            id: anniversary.id,
            title: title,
            date: date,
            annual: annual,
            visibility: visibility
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func deleteAnniversary(_ anniversary: Anniversary) async throws {
        if isDemo {
            anniversaries.removeAll {
                $0.id.caseInsensitiveCompare(anniversary.id) == .orderedSame
            }
            refreshHomeAfterDeletingAnniversary(id: anniversary.id)
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.deleteAnniversary(id: anniversary.id)
        try await loadLocalContent()
        refreshHomeAfterDeletingAnniversary(id: anniversary.id)
        triggerSyncAfterWrite()
    }

    func addCalendarEvent(title: String, start: Date, end: Date?, allDay: Bool) async throws {
        if isDemo { return }
        let identity = try localIdentity()
        _ = try offlineStore?.createCalendarEvent(
            coupleId: identity.coupleId,
            ownerId: identity.userId,
            title: title,
            start: start,
            end: end,
            allDay: allDay
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func updateCalendarEvent(
        _ event: CalendarEvent,
        title: String,
        start: Date,
        end: Date?,
        allDay: Bool
    ) async throws {
        let sourceID = event.recurrenceSourceId ?? event.id
        if isDemo {
            let startDelta = start.timeIntervalSince(event.startTime)
            let endDelta = end.flatMap { editedEnd in
                event.endTime.map { editedEnd.timeIntervalSince($0) }
            }
            let editedDuration = end.map { max($0.timeIntervalSince(start), 0) }
            for index in calendarEvents.indices where
                calendarEvents[index].id == sourceID
                    || calendarEvents[index].recurrenceSourceId == sourceID {
                calendarEvents[index].title = title
                calendarEvents[index].startTime = calendarEvents[index].startTime
                    .addingTimeInterval(startDelta)
                if end == nil {
                    calendarEvents[index].endTime = nil
                } else if let currentEnd = calendarEvents[index].endTime, let endDelta {
                    calendarEvents[index].endTime = currentEnd.addingTimeInterval(endDelta)
                } else if let editedDuration {
                    calendarEvents[index].endTime = calendarEvents[index].startTime
                        .addingTimeInterval(editedDuration)
                }
                calendarEvents[index].allDay = allDay
                calendarEvents[index].updatedAt = .now
            }
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.editCalendarEvent(
            id: sourceID,
            title: title,
            start: start,
            end: end,
            allDay: allDay,
            occurrenceStart: event.recurrenceSourceId == nil ? nil : event.startTime,
            occurrenceEnd: event.recurrenceSourceId == nil ? nil : event.endTime
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func deleteCalendarEvent(_ event: CalendarEvent) async throws {
        let sourceID = event.recurrenceSourceId ?? event.id
        if isDemo {
            calendarEvents.removeAll {
                $0.id == sourceID || $0.recurrenceSourceId == sourceID
            }
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.deleteCalendarEvent(id: sourceID)
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func addMemory(
        content: String,
        photos: [SelectedPhoto],
        anniversaryId: String?,
        todoId: String?,
        visibility: Visibility
    ) async throws {
        try Note.validateCreation(text: content, attachmentCount: photos.count)

        if isDemo {
            let note = Note(
                id: UUID().uuidString,
                coupleId: SampleData.relationship.couple!.id,
                ownerId: SampleData.user.id,
                content: content,
                visibility: visibility,
                anniversaryId: anniversaryId,
                todoId: todoId,
                createdAt: Date(),
                updatedAt: Date(),
                associations: [],
                attachments: []
            )
            notes.insert(note, at: 0)
            insertIntoPastNoteCaches(note)
            return
        }
        let identity = try localIdentity()
        _ = try await offlineStore?.createMemory(
            coupleId: identity.coupleId,
            ownerId: identity.userId,
            content: content,
            photos: photos,
            anniversaryId: anniversaryId,
            anniversaryTitle: anniversaries.first(where: { $0.id == anniversaryId })?.title,
            todoId: todoId,
            todoTitle: todos.first(where: { $0.id == todoId })?.title,
            visibility: visibility
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func updateMemory(
        _ note: Note,
        content: String,
        anniversaryId: String?,
        todoId: String?,
        visibility: Visibility
    ) async throws {
        let associations = [
            anniversaryId.flatMap { id in
                anniversaries.first(where: { $0.id == id }).map {
                    NoteAssociation(type: .anniversary, id: id, title: $0.title)
                }
            },
            todoId.flatMap { id in
                todos.first(where: { $0.id == id }).map {
                    NoteAssociation(type: .todo, id: id, title: $0.title)
                }
            },
        ].compactMap { $0 }

        if isDemo {
            guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
            notes[index].content = content
            notes[index].anniversaryId = anniversaryId
            notes[index].todoId = todoId
            notes[index].visibility = visibility
            notes[index].associations = associations
            notes[index].updatedAt = .now
            rebuildPastNoteCaches()
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try offlineStore.editMemory(
            id: note.id,
            content: content,
            anniversaryId: anniversaryId,
            anniversaryTitle: associations.first(where: { $0.type == .anniversary })?.title,
            todoId: todoId,
            todoTitle: associations.first(where: { $0.type == .todo })?.title,
            visibility: visibility
        )
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func deleteMemory(_ note: Note) async throws {
        if isDemo {
            notes.removeAll { $0.id == note.id }
            rebuildPastNoteCaches()
            return
        }
        guard let offlineStore else { throw APIError.invalidResponse }
        try await offlineStore.deleteMemory(id: note.id)
        try await loadLocalContent()
        triggerSyncAfterWrite()
    }

    func updateDisplayName(_ displayName: String) async throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            throw APIError.server(
                status: 400,
                code: "VALIDATION_ERROR",
                message: AppLocalization.string("名字需要在 1 到 100 个字符之间")
            )
        }
        guard let currentUser else { throw APIError.missingSession }

        let updatedUser: User
        if isDemo {
            updatedUser = User(
                id: currentUser.id,
                displayName: trimmedName,
                timezone: currentUser.timezone
            )
        } else {
            updatedUser = try await api.updateMe(displayName: trimmedName)
        }

        applyCurrentUser(updatedUser)
        if !isDemo { try persistSession() }
    }

    func updateCouple(startedOn: Date) async throws {
        if isDemo {
            guard let relationship, var couple = relationship.couple else { return }
            couple.startedOn = startedOn.dateOnlyString
            self.relationship = RelationshipStatus(
                couple: couple,
                members: relationship.members,
                pendingInvite: relationship.pendingInvite
            )
            if let home {
                let calendar = Calendar.current
                let daysTogether = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: startedOn),
                    to: calendar.startOfDay(for: .now)
                ).day
                self.home = HomeData(
                    daysTogether: daysTogether,
                    nextAnniversary: home.nextAnniversary,
                    nextUpcoming: home.nextUpcoming,
                    latestTimelineEntry: home.latestTimelineEntry
                )
            }
            return
        }
        _ = try await api.updateCouple(
            startedOn: startedOn.dateOnlyString,
            timezone: TimeZone.current.identifier
        )
        relationship = try await api.relationshipStatus()
        home = try await api.home()
        try persistSession()
    }

    func signOutDisposition() -> SignOutDisposition {
        guard !isDemo else { return .ready }
        let count = (try? offlineStore?.unsyncedCount()) ?? 0
        return count > 0 ? .requiresDecision(count) : .ready
    }

    func signOutIfSafe() async -> Bool {
        guard signOutDisposition() == .ready else { return false }
        return await performSignOut(discardLocalChanges: false)
    }

    func syncThenSignOut() async -> Bool {
        let result = await synchronize(trigger: .manual, surfaceError: true)
        guard result == .success, signOutDisposition() == .ready else { return false }
        return await performSignOut(discardLocalChanges: false)
    }

    func discardChangesAndSignOut() async -> Bool {
        await performSignOut(discardLocalChanges: true)
    }

    func leaveSpaceIfSafe() async -> Bool {
        guard signOutDisposition() == .ready else { return false }
        return await performLeaveSpace(discardLocalChanges: false)
    }

    func syncThenLeaveSpace() async -> Bool {
        let result = await synchronize(trigger: .manual, surfaceError: true)
        guard result == .success, signOutDisposition() == .ready else { return false }
        return await performLeaveSpace(discardLocalChanges: false)
    }

    func discardChangesAndLeaveSpace() async -> Bool {
        await performLeaveSpace(discardLocalChanges: true)
    }

    func signOut() async {
        _ = await signOutIfSafe()
    }

    private func finishAuthentication(
        user: User,
        relationship: RelationshipStatus,
        trigger: SyncTrigger
    ) async throws {
        currentUser = user
        self.relationship = relationship
        try persistSession()
        if relationship.members.count < 2 {
            phase = .pairing
            return
        }
        try await loadLocalContent()
        phase = .main
        beginConnectivityObservation()
        let result = await synchronize(trigger: trigger, surfaceError: false)
        if case .failed = result, try await localDomainIsEmpty() {
            try await bootstrapFromLegacyAPI()
            try await loadLocalContent()
        }
        if let latestHome = try? await api.home() {
            home = latestHome
            try? offlineStore?.updateCachedHome(latestHome)
        }
    }

    private func synchronize(trigger: SyncTrigger, surfaceError: Bool) async -> SyncRunResult {
        guard let syncCoordinator, !isDemo else { return .success }
        isSyncing = true
        let result = await syncCoordinator.trigger(trigger)
        isSyncing = false
        switch result {
        case .success:
            retryAttempt = 0
            retryTask?.cancel()
            retryTask = nil
            try? await loadLocalContent()
        case .failed(let message):
            if surfaceError { errorMessage = message }
            scheduleRetry()
        case .cancelled:
            break
        }
        return result
    }

    private func scheduleRetry() {
        guard retryTask == nil, phase == .main else { return }
        retryAttempt += 1
        let delay = min(pow(2, Double(min(retryAttempt, 10))), 3_600)
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                self.retryTask = nil
                _ = await self.synchronize(trigger: .retry, surfaceError: false)
            } catch {}
        }
    }

    private func triggerSyncAfterWrite() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.synchronize(trigger: .manual, surfaceError: false)
        }
    }

    private func beginConnectivityObservation() {
        connectivityTask?.cancel()
        connectivityMonitor?.cancel()
        let monitor = ConnectivityMonitor()
        connectivityMonitor = monitor
        connectivityTask = Task { [weak self] in
            var previous: Bool?
            for await connected in monitor.statusStream() {
                guard !Task.isCancelled, let self else { return }
                if connected, previous == false {
                    _ = await self.synchronize(trigger: .networkRestored, surfaceError: false)
                }
                previous = connected
            }
        }
    }

    private func loadLocalContent() async throws {
        guard let snapshot = try await offlineStore?.loadSnapshot() else { return }
        notes = snapshot.notes
        todos = snapshot.todos
        anniversaries = snapshot.anniversaries
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        let end = calendar.date(byAdding: .month, value: 13, to: .now) ?? .now
        calendarEvents = CalendarOccurrenceExpander.expand(
            canonicalEvents: snapshot.canonicalCalendarEvents,
            from: start,
            to: end
        )
        rebuildPastNoteCaches()
    }

    private func localDomainIsEmpty() async throws -> Bool {
        guard let snapshot = try await offlineStore?.loadSnapshot() else { return true }
        return snapshot.notes.isEmpty
            && snapshot.todos.isEmpty
            && snapshot.anniversaries.isEmpty
            && snapshot.canonicalCalendarEvents.isEmpty
            && snapshot.timelineEntries.isEmpty
    }

    private func bootstrapFromLegacyAPI() async throws {
        guard let offlineStore else { return }
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let to = calendar.date(byAdding: .month, value: 13, to: Date()) ?? Date()
        async let homeResult = api.home()
        async let todosResult = api.todos(filter: "all")
        async let anniversariesResult = api.anniversaries()
        async let calendarResult = api.calendar(from: from, to: to)
        let allNotes = try await fetchAllLegacyNotes()
        let latestHome = try await homeResult
        try offlineStore.bootstrap(
            notes: allNotes,
            todos: try await todosResult,
            anniversaries: try await anniversariesResult,
            calendarEvents: try await calendarResult,
            timelineEntries: [latestHome.latestTimelineEntry].compactMap { $0 }
        )
        home = latestHome
        try offlineStore.updateCachedHome(latestHome)
    }

    private func fetchAllLegacyNotes() async throws -> [Note] {
        var result: [Note] = []
        var cursor: String?
        var pages = 0
        repeat {
            pages += 1
            guard pages <= 1_000 else { throw APIError.invalidResponse }
            let page = try await api.notes(query: .all, cursor: cursor)
            result.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return result
    }

    private func persistSession() throws {
        guard let currentUser, let relationship else { return }
        try offlineStore?.saveSession(user: currentUser, relationship: relationship, home: home)
    }

    private func localIdentity() throws -> (coupleId: String, userId: String) {
        guard let coupleId = relationship?.couple?.id, let userId = currentUser?.id else {
            throw APIError.missingSession
        }
        guard offlineStore != nil else {
            throw localStoreInitializationError ?? APIError.invalidResponse
        }
        return (coupleId, userId)
    }

    private func refreshHomeAfterDeletingAnniversary(id: String) {
        guard let currentHome = home,
              currentHome.nextAnniversary?.id.caseInsensitiveCompare(id) == .orderedSame else {
            return
        }
        let updatedHome = HomeData(
            daysTogether: currentHome.daysTogether,
            nextAnniversary: anniversaries.nextUpcomingAnniversary(),
            nextUpcoming: currentHome.nextUpcoming,
            latestTimelineEntry: currentHome.latestTimelineEntry
        )
        home = updatedHome
        if !isDemo { try? offlineStore?.updateCachedHome(updatedHome) }
    }

    private func performLeaveSpace(discardLocalChanges: Bool) async -> Bool {
        guard relationship?.couple != nil else { return false }

        if isDemo {
            relationship = unpairedRelationshipStatus()
            clearLoadedContent()
            phase = .pairing
            return true
        }
        guard let offlineStore else {
            errorMessage = localStoreInitializationError?.localizedDescription
                ?? AppLocalization.string("本地数据库无法打开")
            return false
        }

        await stopSessionActivity()
        do {
            try await api.leaveCouple()
        } catch {
            errorMessage = error.localizedDescription
            beginConnectivityObservation()
            return false
        }

        userDefaults.set(true, forKey: Self.pendingSpaceCleanupDefaultsKey)
        do {
            if discardLocalChanges {
                try await offlineStore.discardPendingMutationsAndLocalData()
            } else {
                try await offlineStore.clearSynchronizedLocalDataForSignOut()
            }
            userDefaults.removeObject(forKey: Self.pendingSpaceCleanupDefaultsKey)
        } catch {
            await api.clearSession()
            currentUser = nil
            relationship = nil
            clearLoadedContent()
            errorMessage = AppLocalization.string("leaveSpaceCleanupFailed",
                defaultValue: "已经退出空间，但本地数据未能安全清理。为保护空间数据，已退出登录：\(error.localizedDescription)"
            )
            phase = .signedOut
            return false
        }

        relationship = (try? await api.relationshipStatus()) ?? unpairedRelationshipStatus()
        clearLoadedContent()
        try? persistSession()
        phase = .pairing
        return true
    }

    private func recoverPendingSpaceCleanup() async -> Bool {
        guard userDefaults.bool(forKey: Self.pendingSpaceCleanupDefaultsKey) else { return true }
        guard let offlineStore else {
            await api.clearSession()
            errorMessage = localStoreInitializationError?.localizedDescription
                ?? AppLocalization.string("本地数据库无法打开")
            return false
        }

        do {
            try await offlineStore.discardPendingMutationsAndLocalData()
            userDefaults.removeObject(forKey: Self.pendingSpaceCleanupDefaultsKey)
            return true
        } catch {
            await api.clearSession()
            currentUser = nil
            relationship = nil
            clearLoadedContent()
            errorMessage = AppLocalization.string("recoverSpaceCleanupFailed",
                defaultValue: "上次退出空间后的本地数据仍未安全清理，请重试：\(error.localizedDescription)"
            )
            return false
        }
    }

    private func performSignOut(discardLocalChanges: Bool) async -> Bool {
        await stopSessionActivity()
        do {
            if discardLocalChanges {
                try await offlineStore?.discardPendingMutationsAndLocalData()
            } else if signOutDisposition() == .ready {
                try await offlineStore?.clearSynchronizedLocalDataForSignOut()
            }
        } catch {
            errorMessage = error.localizedDescription
            beginConnectivityObservation()
            return false
        }
        await api.logOut()
        currentUser = nil
        relationship = nil
        clearLoadedContent()
        phase = .signedOut
        return true
    }

    private func stopSessionActivity() async {
        retryTask?.cancel()
        retryTask = nil
        connectivityTask?.cancel()
        connectivityTask = nil
        connectivityMonitor?.cancel()
        connectivityMonitor = nil
        await syncCoordinator?.cancel()
    }

    private func clearLoadedContent() {
        home = nil
        notes = []
        pastNotes = []
        cachedPastNotes = [:]
        todos = []
        anniversaries = []
        calendarEvents = []
        pendingTodoIDs = []
        selectedNoteQuery = .all
    }

    private func applyCurrentUser(_ user: User) {
        currentUser = user
        guard let relationship else { return }
        let members = relationship.members.map { member in
            if member.id == user.id {
                CoupleMember(id: member.id, displayName: user.displayName)
            } else {
                member
            }
        }
        self.relationship = RelationshipStatus(
            couple: relationship.couple,
            members: members,
            pendingInvite: relationship.pendingInvite
        )
    }

    private func unpairedRelationshipStatus() -> RelationshipStatus {
        RelationshipStatus(
            couple: nil,
            members: currentUser.map {
                [CoupleMember(id: $0.id, displayName: $0.displayName)]
            } ?? [],
            pendingInvite: nil
        )
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch is CancellationError {
            return
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = message.isEmpty
                ? AppLocalization.string("操作失败，请稍后重试")
                : message
        }
    }

    private func loadSampleData(keepingTodoState: Bool = false) {
        currentUser = SampleData.user
        relationship = SampleData.relationship
        home = SampleData.home
        notes = SampleData.notes
        rebuildPastNoteCaches()
        if !keepingTodoState || todos.isEmpty { todos = SampleData.todos }
        anniversaries = [SampleData.anniversary]
        calendarEvents = SampleData.events
    }

    private func rebuildPastNoteCaches() {
        cachedPastNotes = [
            .all: notes.filter { matches($0, query: .all) },
            .photos: notes.filter { matches($0, query: .photos) },
            .anniversaries: notes.filter { matches($0, query: .anniversaries) },
            .completedTodos: notes.filter { matches($0, query: .completedTodos) },
        ]
        pastNotes = cachedPastNotes[selectedNoteQuery] ?? []
    }

    private func insertIntoPastNoteCaches(_ note: Note) {
        for query in Array(cachedPastNotes.keys) where matches(note, query: query) {
            cachedPastNotes[query, default: []].insert(note, at: 0)
        }
        pastNotes = pastNotes(for: selectedNoteQuery)
    }

    private func matches(_ note: Note, query: NoteQuery) -> Bool {
        switch query {
        case .all: true
        case .photos: note.attachments.contains(where: \.isImage)
        case .anniversaries: note.anniversaryId != nil
        case .completedTodos: note.todoId != nil
        }
    }
}

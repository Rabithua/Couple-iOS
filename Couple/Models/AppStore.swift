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

@MainActor
@Observable
final class AppStore {
    let api: APIClient
    private let passkeys: PasskeyService

    var phase: SessionPhase = .launching
    var currentUser: User?
    var relationship: RelationshipStatus?
    var home: HomeData?
    var notes: [Note] = []
    var todos: [Todo] = []
    var anniversaries: [Anniversary] = []
    var calendarEvents: [CalendarEvent] = []
    var selectedNoteQuery: NoteQuery = .all
    var isBusy = false
    var isRefreshing = false
    var errorMessage: String?
    private(set) var isDemo: Bool

    init(
        api: APIClient = APIClient(),
        passkeys: PasskeyService = PasskeyService(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.api = api
        self.passkeys = passkeys
        self.isDemo = environment["COUPLE_DEMO_MODE"] == "1" || arguments.contains("-ui-testing-demo")
    }

    func start() async {
        if isDemo {
            loadSampleData()
            phase = .main
            return
        }

        do {
            guard await api.hasStoredSession, try await api.refreshSession() else {
                phase = .signedOut
                return
            }
            currentUser = try await api.me()
            relationship = try await api.relationshipStatus()
            if relationship?.members.count ?? 0 < 2 {
                phase = .pairing
            } else {
                phase = .main
                await refreshContent()
            }
        } catch {
            await api.clearSession()
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    func enterPreview() {
        isDemo = true
        loadSampleData()
        phase = .main
    }

    func register(displayName: String) async {
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
            currentUser = auth.user
            relationship = try await api.relationshipStatus()
            phase = .pairing
        }
    }

    func signIn() async {
        await runBusy {
            let result = try await api.authenticationOptions()
            let credential = try await passkeys.authenticate(options: result.options)
            let auth = try await api.verifyAuthentication(
                challengeKey: result.challengeKey,
                credential: credential
            )
            try await api.install(tokens: auth.tokens)
            currentUser = auth.user
            relationship = try await api.relationshipStatus()
            if relationship?.members.count ?? 0 < 2 {
                phase = .pairing
            } else {
                phase = .main
                await refreshContent()
            }
        }
    }

    func createInvite() async {
        await runBusy {
            _ = try await api.createInvite()
            relationship = try await api.relationshipStatus()
        }
    }

    func acceptInvite(_ code: String) async {
        await runBusy {
            _ = try await api.acceptInvite(code: code.uppercased())
            relationship = try await api.relationshipStatus()
            phase = .main
            await refreshContent()
        }
    }

    func continueWithoutPartner() async {
        phase = .main
        await refreshContent()
    }

    func refreshContent() async {
        guard !isDemo else {
            loadSampleData(keepingTodoState: true)
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let calendar = Calendar.current
            let from = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let to = calendar.date(byAdding: .month, value: 12, to: Date()) ?? Date()
            async let homeResult = api.home()
            async let notesResult = api.notes(query: selectedNoteQuery)
            async let todosResult = api.todos(filter: "all")
            async let anniversariesResult = api.anniversaries()
            async let calendarResult = api.calendar(from: from, to: to)

            home = try await homeResult
            notes = try await notesResult.items
            todos = try await todosResult
            anniversaries = try await anniversariesResult
            calendarEvents = try await calendarResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectNotes(_ query: NoteQuery) async {
        selectedNoteQuery = query
        if isDemo {
            notes = filteredSampleNotes(query)
            return
        }
        do {
            notes = try await api.notes(query: query).items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleTodo(_ todo: Todo) async {
        let index = todos.firstIndex(where: { $0.id == todo.id })
        if let index {
            todos[index].completed.toggle()
            todos[index].completedAt = todos[index].completed ? Date() : nil
        }
        guard !isDemo else { return }
        do {
            let updated = try await api.setTodo(todo.id, completed: !todo.completed)
            if let index { todos[index] = updated }
        } catch {
            if let index { todos[index] = todo }
            errorMessage = error.localizedDescription
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
        let request = CreateTodoRequest(
            title: title,
            note: nil,
            dueTime: dueDate?.apiISOString,
            visibility: visibility,
            reminderOffset: dueDate == nil ? nil : 60
        )
        todos.insert(try await api.createTodo(request), at: 0)
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
        let request = CreateAnniversaryRequest(
            title: title,
            date: date.dateOnlyString,
            annual: annual,
            visibility: visibility,
            reminderOffset: 1_440
        )
        anniversaries.append(try await api.createAnniversary(request))
    }

    func addCalendarEvent(title: String, start: Date, end: Date?, allDay: Bool) async throws {
        if isDemo { return }
        let request = CreateCalendarEventRequest(
            title: title,
            description: nil,
            allDay: allDay,
            startTime: start.apiISOString,
            endTime: end?.apiISOString,
            timezone: TimeZone.current.identifier,
            yearly: false,
            visibility: .shared,
            reminderOffset: 60
        )
        calendarEvents.append(try await api.createCalendarEvent(request))
    }

    func addMemory(
        content: String,
        photos: [SelectedPhoto],
        anniversaryId: String?,
        todoId: String?,
        visibility: Visibility
    ) async throws {
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
            return
        }

        var attachmentIds: [String] = []
        for photo in photos {
            let upload = try await api.requestUpload(
                PresignedUploadRequest(
                    filename: photo.filename,
                    mimeType: photo.mimeType,
                    size: photo.data.count,
                    width: photo.width,
                    height: photo.height,
                    durationMs: nil
                )
            )
            guard let url = URL(string: upload.presignedUrl) else { throw APIError.invalidResponse }
            try await api.upload(photo.data, to: url, mimeType: photo.mimeType)
            let finalized = try await api.finalizeUpload(objectKey: upload.objectKey)
            attachmentIds.append(finalized.id)
        }

        let note = try await api.createNote(
            CreateNoteRequest(
                content: content,
                visibility: visibility,
                anniversaryId: anniversaryId,
                todoId: todoId,
                attachmentIds: attachmentIds
            )
        )
        notes.insert(note, at: 0)
    }

    func updateCouple(startedOn: Date) async throws {
        guard !isDemo else { return }
        _ = try await api.updateCouple(
            startedOn: startedOn.dateOnlyString,
            timezone: TimeZone.current.identifier
        )
        relationship = try await api.relationshipStatus()
        home = try await api.home()
    }

    func signOut() async {
        await api.logOut()
        currentUser = nil
        relationship = nil
        home = nil
        notes = []
        todos = []
        phase = .signedOut
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSampleData(keepingTodoState: Bool = false) {
        currentUser = SampleData.user
        relationship = SampleData.relationship
        home = SampleData.home
        notes = filteredSampleNotes(selectedNoteQuery)
        if !keepingTodoState || todos.isEmpty { todos = SampleData.todos }
        anniversaries = [SampleData.anniversary]
        calendarEvents = SampleData.events
    }

    private func filteredSampleNotes(_ query: NoteQuery) -> [Note] {
        switch query {
        case .all: SampleData.notes
        case .photos: SampleData.notes.filter { !$0.attachments.isEmpty }
        case .anniversaries: SampleData.notes.filter { $0.anniversaryId != nil }
        case .completedTodos: SampleData.notes.filter { $0.todoId != nil }
        }
    }
}

import Foundation
import Testing
@testable import Couple

@MainActor
struct TodoCompletionTests {
    @Test("Setting completion is explicit and idempotent")
    func settingCompletionIsIdempotent() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "预订晚餐",
            dueDate: nil,
            visibility: .shared
        )
        let completionDate = Date(timeIntervalSince1970: 1_786_435_200)

        let first = try store.setTodoCompletion(
            id: todo.id,
            completed: true,
            completedBy: "owner",
            now: completionDate
        )
        let operationCount = try await store.pendingOperations(limit: 100, now: .distantFuture).count
        let second = try store.setTodoCompletion(
            id: todo.id,
            completed: true,
            completedBy: "owner",
            now: completionDate.addingTimeInterval(1)
        )
        let repeatedOperationCount = try await store.pendingOperations(limit: 100, now: .distantFuture).count

        #expect(first.completed)
        #expect(first.completedAt == completionDate)
        #expect(first.completedBy == "owner")
        #expect(second.completed)
        #expect(second.completedAt == completionDate)
        #expect(repeatedOperationCount == operationCount)
    }

    @Test("Explicit reopen clears completion metadata")
    func reopeningClearsCompletionMetadata() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let todo = try store.createTodo(
            coupleId: "couple",
            ownerId: "owner",
            title: "一起散步",
            dueDate: nil,
            visibility: .shared
        )
        _ = try store.setTodoCompletion(
            id: todo.id,
            completed: true,
            completedBy: "owner"
        )

        let reopened = try store.setTodoCompletion(
            id: todo.id,
            completed: false,
            completedBy: "owner"
        )

        #expect(reopened.completed == false)
        #expect(reopened.completedAt == nil)
        #expect(reopened.completedBy == nil)
    }

    private func makeStore() throws -> (OfflineStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "TodoCompletionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = try OfflineStore.makeInMemory(attachmentRoot: root.appending(path: "attachments"))
        return (store, root)
    }
}

import Foundation
import Testing
@testable import Couple

struct TodoListDisplayOrderTests {
    @Test("Incomplete todos stay first and the latest completion leads completed todos")
    func ordersActiveAndCompletedTodos() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let todos = [
            makeTodo(id: "later", dueTime: baseDate.addingTimeInterval(7_200)),
            makeTodo(
                id: "completed-older",
                completedAt: baseDate.addingTimeInterval(-3_600)
            ),
            makeTodo(id: "sooner", dueTime: baseDate.addingTimeInterval(3_600)),
            makeTodo(
                id: "completed-latest",
                completedAt: baseDate.addingTimeInterval(-1_800)
            ),
            makeTodo(id: "unscheduled")
        ]

        let result = todos.todosOrderedForList()

        #expect(
            result.map(\.id) == [
                "sooner",
                "later",
                "unscheduled",
                "completed-latest",
                "completed-older"
            ]
        )
    }

    private func makeTodo(
        id: String,
        dueTime: Date? = nil,
        completedAt: Date? = nil
    ) -> Todo {
        Todo(
            id: id,
            coupleId: "couple",
            ownerId: "owner",
            title: id,
            note: nil,
            dueTime: dueTime,
            visibility: .shared,
            completed: completedAt != nil,
            completedAt: completedAt,
            completedBy: completedAt == nil ? nil : "owner",
            reminderOffset: nil,
            createdAt: .distantPast,
            updatedAt: completedAt ?? .distantPast
        )
    }
}

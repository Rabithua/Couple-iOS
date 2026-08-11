import Foundation
import XCTest
@testable import Couple

final class TodoDisplayOrderTests: XCTestCase {
    func testIncompleteTodosAreOrderedByDueTimeWithUnscheduledLast() throws {
        let baseDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 8, day: 11, hour: 12)
            )
        )
        let todos = [
            makeTodo(id: "unscheduled-first", dueTime: nil),
            makeTodo(id: "later", dueTime: baseDate.addingTimeInterval(7_200)),
            makeTodo(id: "completed", dueTime: baseDate.addingTimeInterval(-7_200), completed: true),
            makeTodo(id: "overdue", dueTime: baseDate.addingTimeInterval(-3_600)),
            makeTodo(id: "soon", dueTime: baseDate.addingTimeInterval(3_600)),
            makeTodo(id: "unscheduled-second", dueTime: nil)
        ]

        let result = todos.incompleteTodosOrderedByDueTime(limit: 4)

        XCTAssertEqual(result.map(\.id), ["overdue", "soon", "later", "unscheduled-first"])
    }

    func testEqualDueTimesPreserveInputOrder() {
        let dueTime = Date(timeIntervalSince1970: 1_800_000_000)
        let todos = [
            makeTodo(id: "first", dueTime: dueTime),
            makeTodo(id: "second", dueTime: dueTime),
            makeTodo(id: "without-date", dueTime: nil)
        ]

        let result = todos.incompleteTodosOrderedByDueTime(limit: 10)

        XCTAssertEqual(result.map(\.id), ["first", "second", "without-date"])
        XCTAssertTrue(todos.incompleteTodosOrderedByDueTime(limit: 0).isEmpty)
    }

    private func makeTodo(
        id: String,
        dueTime: Date?,
        completed: Bool = false
    ) -> Todo {
        Todo(
            id: id,
            coupleId: "couple",
            ownerId: "owner",
            title: id,
            note: nil,
            dueTime: dueTime,
            visibility: .shared,
            completed: completed,
            completedAt: completed ? .now : nil,
            completedBy: completed ? "owner" : nil,
            reminderOffset: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

import Foundation

struct CalendarScheduleIndex: Equatable, Sendable {
    private let eventsByDay: [Date: [CalendarEvent]]
    private let todosByDay: [Date: [Todo]]

    init(
        events: [CalendarEvent] = [],
        todos: [Todo] = [],
        calendar: Calendar = .current
    ) {
        var groupedEvents = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startTime)
        }
        for day in Array(groupedEvents.keys) {
            groupedEvents[day]?.sort { $0.startTime < $1.startTime }
        }

        var groupedTodos: [Date: [Todo]] = [:]
        for todo in todos {
            guard let dueTime = todo.dueTime else { continue }
            groupedTodos[calendar.startOfDay(for: dueTime), default: []].append(todo)
        }
        for day in Array(groupedTodos.keys) {
            groupedTodos[day]?.sort {
                ($0.dueTime ?? .distantFuture) < ($1.dueTime ?? .distantFuture)
            }
        }

        eventsByDay = groupedEvents
        todosByDay = groupedTodos
    }

    func events(on date: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: date)] ?? []
    }

    func todos(on date: Date, calendar: Calendar = .current) -> [Todo] {
        todosByDay[calendar.startOfDay(for: date)] ?? []
    }

    func hasScheduledItem(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return eventsByDay[day]?.isEmpty == false
            || todosByDay[day]?.isEmpty == false
    }
}

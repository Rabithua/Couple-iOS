import Foundation

struct CalendarScheduleIndex: Equatable, Sendable {
    private let eventsByDay: [Date: [CalendarEvent]]
    private let todosByDay: [Date: [Todo]]
    private let anniversaries: [Anniversary]
    private let calendarTimeZoneIdentifier: String
    let earliestScheduledDate: Date?

    init(
        events: [CalendarEvent] = [],
        todos: [Todo] = [],
        anniversaries: [Anniversary] = [],
        calendar: Calendar = .current
    ) {
        calendarTimeZoneIdentifier = calendar.timeZone.identifier
        var groupedEvents = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startTime)
        }
        for day in Array(groupedEvents.keys) {
            groupedEvents[day]?.sort {
                if $0.allDay != $1.allDay { return $0.allDay }
                return $0.startTime < $1.startTime
            }
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
        self.anniversaries = anniversaries.sorted { $0.title < $1.title }
        let earliestAnniversary = anniversaries.compactMap {
            Anniversary.dateOnly($0.date, calendar: calendar)
        }.min()
        earliestScheduledDate = [groupedEvents.keys.min(), groupedTodos.keys.min(), earliestAnniversary]
            .compactMap { $0 }
            .min()
    }

    func events(on date: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: date)] ?? []
    }

    func todos(on date: Date, calendar: Calendar = .current) -> [Todo] {
        todosByDay[calendar.startOfDay(for: date)] ?? []
    }

    func anniversaries(on date: Date, calendar: Calendar = .current) -> [Anniversary] {
        anniversaries.filter { $0.occurrence(on: date, calendar: calendar) != nil }
    }

    func hasScheduledItem(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return eventsByDay[day]?.isEmpty == false
            || todosByDay[day]?.isEmpty == false
            || !anniversaries(on: day, calendar: calendar).isEmpty
    }
}

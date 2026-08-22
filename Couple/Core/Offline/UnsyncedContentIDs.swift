import Foundation

struct UnsyncedContentIDs: Equatable, Sendable {
    static let empty = Self()

    private let noteIDs: Set<String>
    private let todoIDs: Set<String>
    private let anniversaryIDs: Set<String>
    private let calendarEventIDs: Set<String>
    private let timelineEntryIDs: Set<String>

    init(
        noteIDs: Set<String> = [],
        todoIDs: Set<String> = [],
        anniversaryIDs: Set<String> = [],
        calendarEventIDs: Set<String> = [],
        timelineEntryIDs: Set<String> = []
    ) {
        self.noteIDs = Self.normalized(noteIDs)
        self.todoIDs = Self.normalized(todoIDs)
        self.anniversaryIDs = Self.normalized(anniversaryIDs)
        self.calendarEventIDs = Self.normalized(calendarEventIDs)
        self.timelineEntryIDs = Self.normalized(timelineEntryIDs)
    }

    var isEmpty: Bool {
        noteIDs.isEmpty
            && todoIDs.isEmpty
            && anniversaryIDs.isEmpty
            && calendarEventIDs.isEmpty
            && timelineEntryIDs.isEmpty
    }

    func contains(_ note: Note) -> Bool {
        noteIDs.contains(Self.normalized(note.id))
    }

    func contains(_ todo: Todo) -> Bool {
        todoIDs.contains(Self.normalized(todo.id))
    }

    func contains(_ anniversary: Anniversary) -> Bool {
        anniversaryIDs.contains(Self.normalized(anniversary.id))
    }

    func contains(_ event: CalendarEvent) -> Bool {
        calendarEventIDs.contains(Self.normalized(event.recurrenceSourceId ?? event.id))
    }

    func contains(_ entry: TimelineEntry) -> Bool {
        timelineEntryIDs.contains(Self.normalized(entry.id))
    }

    private static func normalized(_ identifiers: Set<String>) -> Set<String> {
        Set(identifiers.map(normalized))
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.lowercased()
    }
}

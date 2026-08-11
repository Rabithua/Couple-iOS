import Foundation

enum CalendarOccurrenceExpander {
    static func expand(
        canonicalEvents: [CalendarEvent],
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        canonicalEvents.flatMap { event in
            guard event.yearly else {
                return event.startTime < end && (event.endTime ?? event.startTime) >= start ? [event] : []
            }
            return yearlyOccurrences(event, from: start, to: end, calendar: calendar)
        }
        .sorted { $0.startTime < $1.startTime }
    }

    private static func yearlyOccurrences(
        _ source: CalendarEvent,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [CalendarEvent] {
        var eventCalendar = calendar
        if let timezone = TimeZone(identifier: source.timezone) {
            eventCalendar.timeZone = timezone
        }
        let sourceComponents = eventCalendar.dateComponents(
            [.month, .day, .hour, .minute, .second],
            from: source.startTime
        )
        let startYear = eventCalendar.component(.year, from: start) - 1
        let endYear = eventCalendar.component(.year, from: end) + 1
        let duration = source.endTime?.timeIntervalSince(source.startTime)

        return (startYear...endYear).compactMap { year in
            var components = sourceComponents
            components.year = year
            guard let occurrenceStart = eventCalendar.date(from: components),
                  occurrenceStart >= start,
                  occurrenceStart < end else { return nil }
            let occurrenceEnd = duration.map { occurrenceStart.addingTimeInterval($0) }
            let occurrenceKey = "\(source.id)#\(occurrenceStart.dateOnlyString)"
            return CalendarEvent(
                id: occurrenceKey,
                coupleId: source.coupleId,
                ownerId: source.ownerId,
                title: source.title,
                description: source.description,
                allDay: source.allDay,
                startTime: occurrenceStart,
                endTime: occurrenceEnd,
                timezone: source.timezone,
                yearly: true,
                visibility: source.visibility,
                reminderOffset: source.reminderOffset,
                createdAt: source.createdAt,
                updatedAt: source.updatedAt,
                occurrenceId: occurrenceKey,
                recurrenceSourceId: source.id
            )
        }
    }
}

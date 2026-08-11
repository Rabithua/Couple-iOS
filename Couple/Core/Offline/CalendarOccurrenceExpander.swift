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
                return event.startTime <= end && (event.endTime ?? event.startTime) >= start ? [event] : []
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
            [.year, .month, .day, .hour, .minute, .second],
            from: source.startTime
        )
        guard let sourceYear = sourceComponents.year,
              let sourceMonth = sourceComponents.month,
              let sourceDay = sourceComponents.day else { return [] }
        let rangeStartYear = eventCalendar.component(.year, from: start)
        let startYear = max(sourceYear, rangeStartYear - 1)
        let endYear = eventCalendar.component(.year, from: end)
        guard startYear <= endYear else { return [] }
        let duration = source.endTime?.timeIntervalSince(source.startTime)

        return (startYear...endYear).compactMap { year in
            var components = sourceComponents
            components.year = year
            if sourceMonth == 2, sourceDay == 29, !isLeapYear(year) {
                components.day = 28
            }
            guard let occurrenceStart = eventCalendar.date(from: components),
                  occurrenceStart <= end else { return nil }
            let occurrenceEnd = duration.map { occurrenceStart.addingTimeInterval($0) }
            guard occurrenceEnd ?? occurrenceStart >= start else { return nil }
            let occurrenceKey = "\(source.id)~\(year)"
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

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
    }
}

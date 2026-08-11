enum MainPagerRoute: Int, CaseIterable, Hashable {
    case pastCompleted
    case pastAnniversaries
    case pastPhotos
    case pastAll
    case now
    case futureCalendar
    case futureList

    var sectionIndex: Int {
        switch self {
        case .pastCompleted, .pastAnniversaries, .pastPhotos, .pastAll:
            0
        case .now:
            1
        case .futureCalendar, .futureList:
            2
        }
    }

    var isPast: Bool {
        sectionIndex == 0
    }

    var isFuture: Bool {
        sectionIndex == 2
    }

    var pastFilter: PastFilter? {
        switch self {
        case .pastCompleted:
            .completed
        case .pastAnniversaries:
            .anniversaries
        case .pastPhotos:
            .photos
        case .pastAll:
            .all
        case .now, .futureCalendar, .futureList:
            nil
        }
    }

    var futureMode: FutureMode? {
        switch self {
        case .futureCalendar:
            .calendar
        case .futureList:
            .list
        case .pastCompleted, .pastAnniversaries, .pastPhotos, .pastAll, .now:
            nil
        }
    }

    static func past(_ filter: PastFilter) -> Self {
        switch filter {
        case .completed:
            .pastCompleted
        case .anniversaries:
            .pastAnniversaries
        case .photos:
            .pastPhotos
        case .all:
            .pastAll
        }
    }

    static func future(_ mode: FutureMode) -> Self {
        mode == .list ? .futureList : .futureCalendar
    }
}

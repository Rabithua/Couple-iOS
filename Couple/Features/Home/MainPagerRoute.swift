enum MainPagerRoute: Int, CaseIterable, Hashable {
    case pastCompleted
    case pastAnniversaries
    case pastPhotos
    case pastAll
    case now
    case futureCalendar
    case futureList
    case futureSettings

    var sectionIndex: Int {
        switch self {
        case .pastCompleted, .pastAnniversaries, .pastPhotos, .pastAll:
            0
        case .now:
            1
        case .futureCalendar, .futureList, .futureSettings:
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
        case .now, .futureCalendar, .futureList, .futureSettings:
            nil
        }
    }

    var futureMode: FutureMode? {
        switch self {
        case .futureCalendar:
            .calendar
        case .futureList:
            .list
        case .futureSettings:
            .settings
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
        switch mode {
        case .calendar: .futureCalendar
        case .list: .futureList
        case .settings: .futureSettings
        }
    }
}

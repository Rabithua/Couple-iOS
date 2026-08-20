import Foundation

enum CalendarScrollTarget: Hashable, Sendable {
    case month(Date)
    case today(Date)
    case day(Date)
}

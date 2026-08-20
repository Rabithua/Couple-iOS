import Foundation

enum NotificationRoute: String, Sendable {
    case main
    case past
    case futureList
    case futureCalendar
}

struct NotificationDestination: Equatable, Identifiable, Sendable {
    let id = UUID()
    let eventType: String
    let route: NotificationRoute
    let entityType: String?
    let entityId: String?
    let occurrenceDate: Date?

    init?(userInfo: [AnyHashable: Any]) {
        guard let eventType = userInfo["eventType"] as? String,
              let routeValue = userInfo["route"] as? String,
              let route = NotificationRoute(rawValue: routeValue)
        else { return nil }
        self.eventType = eventType
        self.route = route
        entityType = userInfo["entityType"] as? String
        entityId = userInfo["entityId"] as? String
        occurrenceDate = (userInfo["occurrenceDate"] as? String).flatMap(Date.fromDateOnly)
    }
}

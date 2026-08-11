extension Sequence where Element == Todo {
    func incompleteTodosOrderedByDueTime(limit: Int) -> [Todo] {
        guard limit > 0 else { return [] }

        return enumerated()
            .filter { !$0.element.completed }
            .sorted { left, right in
                switch (left.element.dueTime, right.element.dueTime) {
                case let (.some(leftDate), .some(rightDate)) where leftDate != rightDate:
                    leftDate < rightDate
                case (.some, .none):
                    true
                case (.none, .some):
                    false
                default:
                    left.offset < right.offset
                }
            }
            .prefix(limit)
            .map(\.element)
    }
}

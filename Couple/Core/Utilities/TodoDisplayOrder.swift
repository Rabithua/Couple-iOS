extension Sequence where Element == Todo {
    func todosOrderedForList() -> [Todo] {
        enumerated()
            .sorted { left, right in
                if left.element.completed != right.element.completed {
                    return left.element.completed == false
                }

                if left.element.completed {
                    switch (left.element.completedAt, right.element.completedAt) {
                    case let (.some(leftDate), .some(rightDate)) where leftDate != rightDate:
                        return leftDate > rightDate
                    case (.some, .none):
                        return true
                    case (.none, .some):
                        return false
                    default:
                        return left.offset < right.offset
                    }
                }

                switch (left.element.dueTime, right.element.dueTime) {
                case let (.some(leftDate), .some(rightDate)) where leftDate != rightDate:
                    return leftDate < rightDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return left.offset < right.offset
                }
            }
            .map(\.element)
    }

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

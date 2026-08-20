import Foundation

enum ReminderPreset: String, CaseIterable, Identifiable, Sendable {
    case off
    case atTime
    case oneHour
    case oneDay
    case oneWeek

    var id: Self { self }

    var isEnabled: Bool { self != .off }

    var offsetMinutes: Int? {
        switch self {
        case .off: nil
        case .atTime: 0
        case .oneHour: 60
        case .oneDay: 1_440
        case .oneWeek: 10_080
        }
    }

    var title: String {
        switch self {
        case .off: AppLocalization.string("关闭")
        case .atTime: AppLocalization.string("准时")
        case .oneHour: AppLocalization.string("提前 1 小时")
        case .oneDay: AppLocalization.string("提前 1 天")
        case .oneWeek: AppLocalization.string("提前 1 周")
        }
    }

    static func selected(enabled: Bool?, offset: Int?, default fallback: Self) -> Self {
        guard enabled == true else { return .off }
        return Self.allCases.first { $0.offsetMinutes == offset } ?? fallback
    }
}

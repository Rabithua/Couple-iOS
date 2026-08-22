import Foundation

struct SyncToastNotice: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case success
        case pending
        case error
    }

    let id = UUID()
    let kind: Kind
    let message: String
}

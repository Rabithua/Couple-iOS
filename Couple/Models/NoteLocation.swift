import Foundation

struct NoteLocation: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String?

    var displayName: String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return "" }
        return name
    }
}

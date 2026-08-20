import Foundation

struct NoteLocation: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        let latitudeText = latitude.formatted(.number.precision(.fractionLength(4)))
        let longitudeText = longitude.formatted(.number.precision(.fractionLength(4)))
        return "\(latitudeText), \(longitudeText)"
    }
}

import Foundation
import CoreLocation

struct SafeBase: Identifiable, Codable, Sendable {
    let id: String
    let location: CLLocationCoordinate2D
    let createdAt: Date
    let type: SafeBaseType
    let expiresAt: Date?  // nil = permanent

    enum CodingKeys: String, CodingKey {
        case id
        case location
        case createdAt
        case type
        case expiresAt
    }
}

enum SafeBaseType: String, Codable, Sendable {
    case homeBase       // Set at game start
    case missedTag      // Expires at midnight
    case hitTag         // Permanent for game duration
}

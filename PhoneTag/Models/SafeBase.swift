import Foundation
import CoreLocation

struct SafeBase: Identifiable, Codable, Sendable {
    let id: String
    let location: CLLocationCoordinate2D
    let createdAt: Date
    let type: SafeBaseType
    let expiresAt: Date?  // nil = permanent
    /// Radius in metres for collision detection and map display.
    /// Defaults to `safeBaseRadius` if not stored (backward-compat with old data).
    let radius: Double?
    /// Display name of the player who fired this tag (hits only).
    var taggerName: String?
    /// Display name of the player who got hit (hits only, for map label).
    var targetName: String?
    /// User ID of the player who fired this tag (set on miss safe bases for duplicate-location detection).
    var taggerUserId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case location
        case createdAt
        case type
        case expiresAt
        case radius
        case taggerName
        case targetName
        case taggerUserId
    }

    /// Effective radius to use — falls back to the constant for legacy records.
    var effectiveRadius: Double {
        radius ?? GameConstants.safeBaseRadius
    }
}

enum SafeBaseType: String, Codable, Sendable {
    case homeBase       // Set at game start
    case missedTag      // Expires at midnight
    case hitTag         // Permanent for game duration
}

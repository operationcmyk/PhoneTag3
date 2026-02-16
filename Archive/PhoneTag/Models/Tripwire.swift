import Foundation
import CoreLocation

struct Tripwire: Identifiable, Codable, Sendable {
    let id: String
    let placedBy: String
    let gameId: String
    let path: [CLLocationCoordinate2D]
    let placedAt: Date
    var triggeredBy: String?
    var triggeredAt: Date?
    let isPermanent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case placedBy
        case gameId
        case path
        case placedAt
        case triggeredBy
        case triggeredAt
        case isPermanent
    }
}

import Foundation

struct Tag: Identifiable, Codable, Sendable {
    let id: String
    let gameId: String
    let fromUserId: String
    let targetUserId: String
    let guessedLocation: GeoPoint
    let timestamp: Date
    var result: TagResult?
    let tagType: TagType

    var isHit: Bool {
        if case .hit = result { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case id
        case gameId
        case fromUserId
        case targetUserId
        case guessedLocation
        case timestamp
        case result
        case tagType
    }
}

enum TagResult: Codable, Sendable {
    case hit(actualLocation: GeoPoint, distance: Double, targetName: String)
    case miss(distance: Double)
    case blocked(reason: BlockReason)

    enum CodingKeys: String, CodingKey {
        case type
        case actualLocation
        case distance
        case reason
        case targetName
    }

    enum ResultType: String, Codable {
        case hit, miss, blocked
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hit(let location, let distance, let targetName):
            try container.encode(ResultType.hit, forKey: .type)
            try container.encode(location, forKey: .actualLocation)
            try container.encode(distance, forKey: .distance)
            try container.encode(targetName, forKey: .targetName)
        case .miss(let distance):
            try container.encode(ResultType.miss, forKey: .type)
            try container.encode(distance, forKey: .distance)
        case .blocked(let reason):
            try container.encode(ResultType.blocked, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResultType.self, forKey: .type)
        switch type {
        case .hit:
            let location = try container.decode(GeoPoint.self, forKey: .actualLocation)
            let distance = try container.decode(Double.self, forKey: .distance)
            let targetName = try container.decodeIfPresent(String.self, forKey: .targetName) ?? "Unknown"
            self = .hit(actualLocation: location, distance: distance, targetName: targetName)
        case .miss:
            let distance = try container.decode(Double.self, forKey: .distance)
            self = .miss(distance: distance)
        case .blocked:
            let reason = try container.decode(BlockReason.self, forKey: .reason)
            self = .blocked(reason: reason)
        }
    }
}

enum BlockReason: String, Codable, Sendable {
    case homeBase
    case safeBase
    case outOfTags
    case playerEliminated
}

enum TagType: String, Codable, Sendable {
    case basic          // ~80m radius (~1 block)
    case wideRadius     // ~300m radius (3-5 blocks)
}

/// GeoPoint wrapper for Firebase compatibility
struct GeoPoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}

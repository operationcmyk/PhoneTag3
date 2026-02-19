import Foundation
import CoreLocation
import SwiftUI

struct PlayerState: Codable, Sendable {
    var strikes: Int                        // 3 at game start
    var tagsRemainingToday: Int             // Resets to dailyTagLimit at midnight (not additive)
    var lastTagResetDate: Date              // Date of the last daily reset
    var homeBase1: CLLocationCoordinate2D?
    var homeBase2: CLLocationCoordinate2D?

    /// Convenience accessor — currently the game uses a single home base (`homeBase1`).
    var homeBase: CLLocationCoordinate2D? {
        get { homeBase1 }
        set { homeBase1 = newValue }
    }
    var safeBases: [SafeBase]
    var isActive: Bool                      // false when strikes = 0
    var tripwires: [Tripwire]
    var purchasedTags: PurchasedTags

    enum CodingKeys: String, CodingKey {
        case strikes
        case tagsRemainingToday
        case lastTagResetDate
        case homeBase1
        case homeBase2
        case safeBases
        case isActive
        case tripwires
        case purchasedTags
    }
}

// Firebase RTDB drops empty arrays (stores as null/missing).
// Override only init(from:) in an extension so the memberwise initializer is preserved.
extension PlayerState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strikes = try c.decode(Int.self, forKey: .strikes)
        tagsRemainingToday = try c.decode(Int.self, forKey: .tagsRemainingToday)
        lastTagResetDate = try c.decode(Date.self, forKey: .lastTagResetDate)
        homeBase1 = try c.decodeIfPresent(CLLocationCoordinate2D.self, forKey: .homeBase1)
        homeBase2 = try c.decodeIfPresent(CLLocationCoordinate2D.self, forKey: .homeBase2)
        safeBases = (try? c.decodeIfPresent([SafeBase].self, forKey: .safeBases)) ?? []
        isActive = try c.decode(Bool.self, forKey: .isActive)
        tripwires = (try? c.decodeIfPresent([Tripwire].self, forKey: .tripwires)) ?? []
        purchasedTags = try c.decode(PurchasedTags.self, forKey: .purchasedTags)
    }
}

struct PurchasedTags: Codable, Sendable {
    var extraBasicTags: Int
    var wideRadiusTags: Int
    var radars: Int
    var tripwires: Int

    enum CodingKeys: String, CodingKey {
        case extraBasicTags
        case wideRadiusTags
        case radars
        case tripwires
    }
}

/// Result of using a radar item — shows two possible locations for a target.
struct RadarResult: Sendable {
    let locations: [CLLocationCoordinate2D] // always 2 — one real (jittered), one decoy
    let radius: CLLocationDistance          // ~610m (2000ft)
    let targetName: String
}

/// Items available in the player's arsenal drawer.
enum ArsenalItem: String, CaseIterable, Identifiable, Sendable {
    case basicTag
    case wideRadiusTag
    case radar
    case tripwire

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basicTag:     return "Tag"
        case .wideRadiusTag: return "Big Tag"
        case .radar:        return "Radar"
        case .tripwire:     return "Tripwire"
        }
    }

    var icon: String {
        switch self {
        case .basicTag:     return "scope"
        case .wideRadiusTag: return "circle.dotted.and.circle"
        case .radar:        return "dot.radiowaves.left.and.right"
        case .tripwire:     return "sensor.fill"
        }
    }

    /// Color derived from legacy bomb assets.
    var legacyColor: Color {
        switch self {
        case .basicTag:     return GameConstants.arsenalTagColor      // Hot Pink
        case .wideRadiusTag: return GameConstants.arsenalBigTagColor  // Gold
        case .radar:        return GameConstants.arsenalRadarColor    // Blue
        case .tripwire:     return GameConstants.arsenalTripwireColor // Purple
        }
    }

    var description: String {
        switch self {
        case .basicTag:     return "~1 block radius"
        case .wideRadiusTag: return "~3-5 block radius"
        case .radar:        return "Ping a player's area"
        case .tripwire:     return "Place at your location"
        }
    }

    /// Returns the count available for this item from a player state.
    func count(from state: PlayerState) -> Int {
        switch self {
        case .basicTag:
            return state.tagsRemainingToday + state.purchasedTags.extraBasicTags
        case .wideRadiusTag:
            return state.purchasedTags.wideRadiusTags
        case .radar:
            return state.purchasedTags.radars
        case .tripwire:
            return state.purchasedTags.tripwires
        }
    }

    func isAvailable(from state: PlayerState) -> Bool {
        state.isActive && count(from: state) > 0
    }
}

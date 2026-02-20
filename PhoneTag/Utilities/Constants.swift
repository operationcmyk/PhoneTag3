import Foundation
import CoreLocation
import SwiftUI

enum GameConstants {
    // Tag Radii (in meters)
    static let basicTagRadius: CLLocationDistance = 80       // ~1 NYC block
    static let wideRadiusTagRadius: CLLocationDistance = 300 // ~3-5 blocks

    // Game Settings
    static let startingStrikes = 3
    static let dailyTagLimit = 5
    static let homeBaseRadius: CLLocationDistance = 50       // meters
    static let safeBaseRadius: CLLocationDistance = 50       // meters

    // Player & Game Limits
    static let maxPlayersPerGame = 5
    static let maxAddablePlayers = 4
    static let gameTitleMaxLength = 8
    static let registrationCodeLength = 6

    // Player Colors (from legacy bomb assets)
    static let playerColors: [Color] = [
        Color(red: 0.90, green: 0.10, blue: 0.43),  // Hot Pink (bomb_1)
        Color(red: 0.55, green: 0.75, blue: 0.15),  // Lime Green (bomb_2)
        Color(red: 0.96, green: 0.77, blue: 0.09),  // Gold (bomb_3)
        Color(red: 0.48, green: 0.31, blue: 0.69),  // Purple (bomb_4)
        Color(red: 0.18, green: 0.43, blue: 0.71),  // Blue (bomb_5)
    ]

    // Arsenal Item Colors (derived from legacy bomb palette)
    static let arsenalTagColor = Color(red: 0.90, green: 0.10, blue: 0.43)         // Hot Pink
    static let arsenalBigTagColor = Color(red: 0.96, green: 0.77, blue: 0.09)      // Gold
    static let arsenalRadarColor = Color(red: 0.18, green: 0.43, blue: 0.71)       // Blue
    static let arsenalTripwireColor = Color(red: 0.48, green: 0.31, blue: 0.69)    // Purple
    static let arsenalActionRed = Color(red: 0.82, green: 0.0, blue: 0.0)          // Legacy buy button #D20000
    static let arsenalGold = Color(red: 1.0, green: 0.925, blue: 0.0)              // Legacy gold text #FFEC00

    // Tripwire Settings
    static let tripwireRadius: CLLocationDistance = 15      // ~50ft

    // Radar Settings
    static let radarRadius: CLLocationDistance = 610         // ~2000ft
    static let radarDuration: TimeInterval = 20             // seconds visible
    static let radarJitter: CLLocationDistance = 300         // max offset for real location within circle
    static let radarDecoyMinDistance: CLLocationDistance = 1500  // min distance between real and decoy circles
    static let radarDecoyMaxDistance: CLLocationDistance = 3000  // max distance between real and decoy circles

    // Location Update Settings
    static let significantLocationChangeDistance: CLLocationDistance = 100
    static let backgroundLocationUpdateInterval: TimeInterval = 300 // 5 minutes

    // Firebase Paths
    enum FirebasePath {
        static let users = "users"
        static let games = "games"
        static let tags = "tags"
        static let locations = "locations"
        static let friendRequests = "friendRequests"
        static let registrationCodes = "registrationCodes"
        static let fcmTokens = "fcmTokens"
    }
}

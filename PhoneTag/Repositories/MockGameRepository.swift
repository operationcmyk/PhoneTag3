import Foundation
import CoreLocation

@MainActor
@Observable
final class MockGameRepository: GameRepositoryProtocol {
    var games: [Game]

    /// Simulated "actual" player locations for tag validation.
    /// In production this comes from Firebase `/locations/{userId}/current`.
    var playerLocations: [String: CLLocationCoordinate2D] = [
        "mock-user-001": CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        "mock-user-002": CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
        "mock-user-003": CLLocationCoordinate2D(latitude: 40.7306, longitude: -73.9352),
        "mock-user-004": CLLocationCoordinate2D(latitude: 40.6892, longitude: -74.0445),
        "mock-user-005": CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857),
    ]

    var playerNames: [String: String] = [
        "mock-user-001": "Player 1",
        "mock-user-002": "Player 2",
        "mock-user-003": "Player 3",
        "mock-user-004": "Player 4",
        "mock-user-005": "Player 5",
    ]

    init() {
        let now = Date()

        let defaultPlayerState = PlayerState(
            strikes: GameConstants.startingStrikes,
            tagsRemainingToday: GameConstants.dailyTagLimit,
            lastTagResetDate: now,
            homeBase1: nil,
            homeBase2: nil,
            safeBases: [],
            isActive: true,
            tripwires: [],
            purchasedTags: PurchasedTags(extraBasicTags: 0, wideRadiusTags: 3, radars: 2, tripwires: 1)
        )

        var activePlayer1 = defaultPlayerState
        activePlayer1.homeBase1 = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        activePlayer1.homeBase2 = CLLocationCoordinate2D(latitude: 40.7200, longitude: -74.0010)
        activePlayer1.strikes = 2

        var activePlayer2 = defaultPlayerState
        activePlayer2.homeBase1 = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        activePlayer2.homeBase2 = CLLocationCoordinate2D(latitude: 40.7550, longitude: -73.9900)

        games = [
            // Active game with home bases set
            Game(
                id: "game-001",
                title: "NYC",
                registrationCode: "AB12CD",
                createdAt: now.addingTimeInterval(-86400 * 3),
                players: [
                    "mock-user-001": activePlayer1,
                    "mock-user-002": activePlayer2,
                    "mock-user-003": defaultPlayerState,
                ],
                createdBy: "mock-user-001",
                status: .active,
                startedAt: now.addingTimeInterval(-86400 * 2),
                endedAt: nil
            ),
            // Waiting game — home base not yet set
            Game(
                id: "game-002",
                title: "BK",
                registrationCode: "XY34ZW",
                createdAt: now.addingTimeInterval(-3600),
                players: [
                    "mock-user-001": defaultPlayerState,
                    "mock-user-004": defaultPlayerState,
                ],
                createdBy: "mock-user-004",
                status: .waiting,
                startedAt: nil,
                endedAt: nil
            ),
            // Completed game
            Game(
                id: "game-003",
                title: "MIDTOWN",
                registrationCode: "QR56ST",
                createdAt: now.addingTimeInterval(-86400 * 10),
                players: [
                    "mock-user-001": {
                        var s = activePlayer1
                        s.strikes = 0
                        s.isActive = false
                        return s
                    }(),
                    "mock-user-005": activePlayer2,
                ],
                createdBy: "mock-user-001",
                status: .completed,
                startedAt: now.addingTimeInterval(-86400 * 9),
                endedAt: now.addingTimeInterval(-86400 * 2)
            ),
        ]
    }

    func fetchGames(for userId: String) async -> [Game] {
        games.filter { $0.players.keys.contains(userId) }
    }

    func fetchGame(by id: String) async -> Game? {
        games.first { $0.id == id }
    }

    func createGame(createdBy: String, title: String, playerIds: [String]) async -> Game {
        let defaultPlayerState = PlayerState(
            strikes: GameConstants.startingStrikes,
            tagsRemainingToday: GameConstants.dailyTagLimit,
            lastTagResetDate: Date(),
            homeBase1: nil,
            homeBase2: nil,
            safeBases: [],
            isActive: true,
            tripwires: [],
            purchasedTags: PurchasedTags(extraBasicTags: 0, wideRadiusTags: 3, radars: 2, tripwires: 1)
        )

        var players: [String: PlayerState] = [:]
        let allIds = [createdBy] + playerIds
        for id in allIds {
            players[id] = defaultPlayerState
        }

        let game = Game(
            id: "game-\(UUID().uuidString.prefix(8).lowercased())",
            title: title,
            registrationCode: Self.generateCode(),
            createdAt: Date(),
            players: players,
            createdBy: createdBy,
            status: .waiting,
            startedAt: nil,
            endedAt: nil
        )

        games.append(game)
        return game
    }

    func updatePlayerState(gameId: String, userId: String, state: PlayerState) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].players[userId] = state
    }

    func deleteGame(id: String) async {
        games.removeAll { $0.id == id }
    }

    func leaveGame(gameId: String, userId: String) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].players[userId]?.isActive = false
        let activePlayers = games[idx].players.values.filter(\.isActive)
        if activePlayers.count <= 1 {
            games[idx].status = .completed
            games[idx].endedAt = Date()
        }
    }

    func joinGame(byCode code: String, userId: String) async -> Game? {
        guard let idx = games.firstIndex(where: {
            $0.registrationCode == code.uppercased()
        }) else { return nil }

        // Already a player — just return the game
        if games[idx].players[userId] != nil { return games[idx] }

        guard games[idx].status == .waiting else { return nil }

        let newState = PlayerState(
            strikes: GameConstants.startingStrikes,
            tagsRemainingToday: GameConstants.dailyTagLimit,
            lastTagResetDate: Date(),
            homeBase1: nil,
            homeBase2: nil,
            safeBases: [],
            isActive: true,
            tripwires: [],
            purchasedTags: PurchasedTags(extraBasicTags: 0, wideRadiusTags: 0, radars: 0, tripwires: 0)
        )
        games[idx].players[userId] = newState
        return games[idx]
    }

    // MARK: - Tag Validation

    func submitTag(
        gameId: String,
        fromUserId: String,
        guessedLocation: CLLocationCoordinate2D,
        tagType: TagType
    ) async -> TagResult {
        guard let gameIdx = games.firstIndex(where: { $0.id == gameId }) else {
            return .blocked(reason: .outOfTags)
        }

        let game = games[gameIdx]

        // Check tagger has tags remaining for this tag type
        guard let taggerState = game.players[fromUserId] else {
            return .blocked(reason: .outOfTags)
        }

        switch tagType {
        case .basic:
            let available = taggerState.tagsRemainingToday + taggerState.purchasedTags.extraBasicTags
            guard available > 0 else { return .blocked(reason: .outOfTags) }
            if taggerState.tagsRemainingToday > 0 {
                games[gameIdx].players[fromUserId]?.tagsRemainingToday -= 1
            } else {
                games[gameIdx].players[fromUserId]?.purchasedTags.extraBasicTags -= 1
            }
        case .wideRadius:
            guard taggerState.purchasedTags.wideRadiusTags > 0 else { return .blocked(reason: .outOfTags) }
            games[gameIdx].players[fromUserId]?.purchasedTags.wideRadiusTags -= 1
        }

        let guessedCL = CLLocation(latitude: guessedLocation.latitude, longitude: guessedLocation.longitude)
        let tagRadius = tagType == .basic ? GameConstants.basicTagRadius : GameConstants.wideRadiusTagRadius

        var closestDistance = Double.greatestFiniteMagnitude
        var hitPlayerId: String?

        // Check every other active player
        for (playerId, playerState) in game.players where playerId != fromUserId && playerState.isActive {
            guard let actualCoord = playerLocations[playerId] else { continue }
            let actualCL = CLLocation(latitude: actualCoord.latitude, longitude: actualCoord.longitude)
            let distance = guessedCL.distance(from: actualCL)

            if distance < closestDistance {
                closestDistance = distance
            }

            guard distance <= tagRadius else { continue }

            // Check if target is at either home base
            for homeBase in [playerState.homeBase1, playerState.homeBase2].compactMap({ $0 }) {
                let homeBaseCL = CLLocation(latitude: homeBase.latitude, longitude: homeBase.longitude)
                if actualCL.distance(from: homeBaseCL) <= GameConstants.homeBaseRadius {
                    return .blocked(reason: .homeBase)
                }
            }

            // Check if target is at any safe base
            let inSafeBase = playerState.safeBases.contains { safeBase in
                let sbCL = CLLocation(latitude: safeBase.location.latitude, longitude: safeBase.location.longitude)
                return actualCL.distance(from: sbCL) <= GameConstants.safeBaseRadius
            }
            if inSafeBase {
                return .blocked(reason: .safeBase)
            }

            hitPlayerId = playerId
        }

        if let hitId = hitPlayerId {
            // HIT — decrement target's strikes
            let actualCoord = playerLocations[hitId]!
            games[gameIdx].players[hitId]?.strikes -= 1

            // Check for elimination
            if let newStrikes = games[gameIdx].players[hitId]?.strikes, newStrikes <= 0 {
                games[gameIdx].players[hitId]?.isActive = false
                checkGameCompletion(gameIdx: gameIdx)
            }

            // Create permanent safe base at target's actual location (basic-tag-sized)
            let permanentBase = SafeBase(
                id: UUID().uuidString,
                location: actualCoord,
                createdAt: Date(),
                type: .hitTag,
                expiresAt: nil,
                radius: GameConstants.basicTagRadius
            )
            games[gameIdx].players[hitId]?.safeBases.append(permanentBase)

            return .hit(
                actualLocation: GeoPoint(latitude: actualCoord.latitude, longitude: actualCoord.longitude),
                distance: closestDistance,
                targetName: playerNames[hitId] ?? "Unknown"
            )
        } else {
            // MISS — create temporary safe base at guessed location (expires at midnight)
            let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)

            // Give safe base to closest active opponent
            let closestOpponent = game.players
                .filter { $0.key != fromUserId && $0.value.isActive }
                .min { a, b in
                    guard let aCoord = playerLocations[a.key],
                          let bCoord = playerLocations[b.key] else { return false }
                    let aDist = guessedCL.distance(from: CLLocation(latitude: aCoord.latitude, longitude: aCoord.longitude))
                    let bDist = guessedCL.distance(from: CLLocation(latitude: bCoord.latitude, longitude: bCoord.longitude))
                    return aDist < bDist
                }

            if let opponentId = closestOpponent?.key {
                let tempBase = SafeBase(
                    id: UUID().uuidString,
                    location: guessedLocation,
                    createdAt: Date(),
                    type: .missedTag,
                    expiresAt: midnight,
                    radius: GameConstants.safeBaseRadius
                )
                games[gameIdx].players[opponentId]?.safeBases.append(tempBase)
            }

            return .miss(distance: closestDistance)
        }
    }

    // MARK: - Arsenal Actions

    func decrementItem(gameId: String, userId: String, item: ArsenalItem) {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        switch item {
        case .basicTag:
            if games[idx].players[userId]?.tagsRemainingToday ?? 0 > 0 {
                games[idx].players[userId]?.tagsRemainingToday -= 1
            } else {
                games[idx].players[userId]?.purchasedTags.extraBasicTags -= 1
            }
        case .wideRadiusTag:
            games[idx].players[userId]?.purchasedTags.wideRadiusTags -= 1
        case .radar:
            games[idx].players[userId]?.purchasedTags.radars -= 1
        case .tripwire:
            games[idx].players[userId]?.purchasedTags.tripwires -= 1
        }
    }

    func useRadar(gameId: String, userId: String) {
        decrementItem(gameId: gameId, userId: userId, item: .radar)
    }

    func placeTripwire(gameId: String, userId: String, tripwire: Tripwire) {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].players[userId]?.tripwires.append(tripwire)
        decrementItem(gameId: gameId, userId: userId, item: .tripwire)
    }

    // MARK: - Purchases

    func purchaseItem(userId: String, product: StoreProduct) async {
        for idx in games.indices {
            guard games[idx].players[userId] != nil else { continue }
            guard games[idx].status != .completed else { continue }
            switch product.item {
            case .basicTag:
                games[idx].players[userId]?.purchasedTags.extraBasicTags += product.quantity
            case .wideRadiusTag:
                games[idx].players[userId]?.purchasedTags.wideRadiusTags += product.quantity
            case .radar:
                games[idx].players[userId]?.purchasedTags.radars += product.quantity
            case .tripwire:
                games[idx].players[userId]?.purchasedTags.tripwires += product.quantity
            }
        }
    }

    // MARK: - Daily Reset

    func resetDailyTagsIfNeeded(gameId: String, userId: String) {
        guard let idx = games.firstIndex(where: { $0.id == gameId }),
              let state = games[idx].players[userId] else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastReset = calendar.startOfDay(for: state.lastTagResetDate)

        guard today > lastReset else { return }

        // Reset daily tags to exactly the limit — never additive
        games[idx].players[userId]?.tagsRemainingToday = GameConstants.dailyTagLimit
        games[idx].players[userId]?.lastTagResetDate = Date()

        // Also expire any midnight safe bases
        games[idx].players[userId]?.safeBases.removeAll { safeBase in
            if let expiresAt = safeBase.expiresAt {
                return Date() >= expiresAt
            }
            return false
        }
    }

    func deductStrikeForInactivity(gameId: String, userId: String) async -> (playerName: String, wasEliminated: Bool)? {
        guard let idx = games.firstIndex(where: { $0.id == gameId }),
              var state = games[idx].players[userId],
              state.isActive,
              state.strikes > 0 else { return nil }
        state.strikes = max(0, state.strikes - 1)
        if state.strikes == 0 { state.isActive = false }
        games[idx].players[userId] = state
        let name = playerNames[userId] ?? "Player"
        return (playerName: name, wasEliminated: state.strikes == 0)
    }

    // MARK: - Private

    private func checkGameCompletion(gameIdx: Int) {
        let activePlayers = games[gameIdx].players.values.filter(\.isActive)
        if activePlayers.count <= 1 {
            games[gameIdx].status = .completed
            games[gameIdx].endedAt = Date()
        }
    }

    private static func generateCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<GameConstants.registrationCodeLength).map { _ in
            chars.randomElement()!
        })
    }
}

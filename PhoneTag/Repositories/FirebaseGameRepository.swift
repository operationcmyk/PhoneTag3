import Foundation
import CoreLocation
@preconcurrency import FirebaseDatabase

/// Shared JSON encoder/decoder configured for Firebase millisecond timestamps.
private let fbEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .millisecondsSince1970
    return e
}()

private let fbDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .millisecondsSince1970
    return d
}()

@MainActor
final class FirebaseGameRepository: GameRepositoryProtocol {
    private let database = Database.database().reference()

    // MARK: - Fetch

    func fetchGames(for userId: String) async -> [Game] {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.users)
                .child(userId)
                .child("activeGameIds")
                .getData()
            let gameIds = (snapshot.value as? [String]) ?? []
            var games: [Game] = []
            for gameId in gameIds {
                if let game = await fetchGame(by: gameId) {
                    games.append(game)
                }
            }
            return games
        } catch {
            return []
        }
    }

    func fetchGame(by id: String) async -> Game? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.games)
                .child(id)
                .getData()
            guard snapshot.exists(), let value = snapshot.value else { return nil }
            return try decodeGame(id: id, from: value)
        } catch {
            return nil
        }
    }

    // MARK: - Create

    func createGame(createdBy: String, title: String, playerIds: [String]) async -> Game {
        let ref = database.child(GameConstants.FirebasePath.games).childByAutoId()
        let gameId = ref.key ?? UUID().uuidString

        let defaultState = PlayerState(
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

        let allPlayerIds = ([createdBy] + playerIds)
        var players: [String: PlayerState] = [:]
        for pid in allPlayerIds { players[pid] = defaultState }

        let game = Game(
            id: gameId,
            title: title,
            registrationCode: Self.generateCode(),
            createdAt: Date(),
            players: players,
            createdBy: createdBy,
            status: .waiting,
            startedAt: nil,
            endedAt: nil
        )

        do {
            let dict = try encodeGame(game)
            try await ref.setValue(dict)

            // Add this gameId to every player's activeGameIds list
            for pid in allPlayerIds {
                try await appendGameId(gameId, toUser: pid)
            }
        } catch {
            // Return the in-memory game even if the write failed
        }
        return game
    }

    // MARK: - Update

    func updatePlayerState(gameId: String, userId: String, state: PlayerState) async {
        do {
            let data = try fbEncoder.encode(state)
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(gameId)
                .child("players")
                .child(userId)
                .setValue(dict)

            // Auto-activate the game if all players now have a home base
            await activateIfReady(gameId: gameId)
        } catch {}
    }

    func leaveGame(gameId: String, userId: String) async {
        // Remove this game from the leaving user's home screen list
        try? await removeGameId(gameId, fromUser: userId)

        // Mark the player as inactive in the game record
        guard var game = await fetchGame(by: gameId),
              var state = game.players[userId] else { return }
        state.isActive = false
        game.players[userId] = state
        await updatePlayerState(gameId: gameId, userId: userId, state: state)

        // If ≤1 active player remains, complete the game
        let remaining = game.players.values.filter(\.isActive)
        if remaining.count <= 1 {
            do {
                try await database.child(GameConstants.FirebasePath.games).child(gameId)
                    .child("status").setValue(GameStatus.completed.rawValue)
                try await database.child(GameConstants.FirebasePath.games).child(gameId)
                    .child("endedAt").setValue(ServerValue.timestamp())
            } catch {}
        }
    }

    func deleteGame(id: String) async {
        do {
            // Collect player IDs before deleting
            if let game = await fetchGame(by: id) {
                for pid in game.players.keys {
                    try await removeGameId(id, fromUser: pid)
                }
            }
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(id)
                .removeValue()
        } catch {}
    }

    // MARK: - Tag Submission (client-side validation; replace with Cloud Functions later)

    func submitTag(
        gameId: String,
        fromUserId: String,
        guessedLocation: CLLocationCoordinate2D,
        tagType: TagType
    ) async -> TagResult {
        guard var game = await fetchGame(by: gameId),
              var taggerState = game.players[fromUserId] else {
            return .blocked(reason: .outOfTags)
        }

        // Check availability and decrement
        switch tagType {
        case .basic:
            let available = taggerState.tagsRemainingToday + taggerState.purchasedTags.extraBasicTags
            guard available > 0 else { return .blocked(reason: .outOfTags) }
            if taggerState.tagsRemainingToday > 0 {
                taggerState.tagsRemainingToday -= 1
            } else {
                taggerState.purchasedTags.extraBasicTags -= 1
            }
        case .wideRadius:
            guard taggerState.purchasedTags.wideRadiusTags > 0 else { return .blocked(reason: .outOfTags) }
            taggerState.purchasedTags.wideRadiusTags -= 1
        }
        await updatePlayerState(gameId: gameId, userId: fromUserId, state: taggerState)
        game.players[fromUserId] = taggerState

        let guessedCL = CLLocation(latitude: guessedLocation.latitude, longitude: guessedLocation.longitude)
        let tagRadius = tagType == .basic ? GameConstants.basicTagRadius : GameConstants.wideRadiusTagRadius

        var closestDistance = Double.greatestFiniteMagnitude
        var hitPlayerId: String?

        for (playerId, playerState) in game.players where playerId != fromUserId && playerState.isActive {
            guard let actualCoord = await fetchPlayerLocation(userId: playerId) else { continue }
            let actualCL = CLLocation(latitude: actualCoord.latitude, longitude: actualCoord.longitude)
            let distance = guessedCL.distance(from: actualCL)
            if distance < closestDistance { closestDistance = distance }
            guard distance <= tagRadius else { continue }

            // Check home bases
            let isAtHomeBase = [playerState.homeBase1, playerState.homeBase2]
                .compactMap { $0 }
                .contains { hb in
                    actualCL.distance(from: CLLocation(latitude: hb.latitude, longitude: hb.longitude))
                        <= GameConstants.homeBaseRadius
                }
            if isAtHomeBase { return .blocked(reason: .homeBase) }

            // Check safe bases
            let isAtSafeBase = playerState.safeBases.contains { sb in
                actualCL.distance(from: CLLocation(latitude: sb.location.latitude, longitude: sb.location.longitude))
                    <= GameConstants.safeBaseRadius
            }
            if isAtSafeBase { return .blocked(reason: .safeBase) }

            hitPlayerId = playerId
        }

        if let hitId = hitPlayerId {
            guard var targetState = game.players[hitId],
                  let actualCoord = await fetchPlayerLocation(userId: hitId) else {
                return .miss(distance: closestDistance)
            }

            targetState.strikes = max(0, targetState.strikes - 1)
            if targetState.strikes == 0 { targetState.isActive = false }

            let permanentBase = SafeBase(
                id: UUID().uuidString,
                location: actualCoord,
                createdAt: Date(),
                type: .hitTag,
                expiresAt: nil
            )
            targetState.safeBases.append(permanentBase)
            await updatePlayerState(gameId: gameId, userId: hitId, state: targetState)
            await checkAndCompleteGame(gameId: gameId)

            let targetName = await fetchDisplayName(userId: hitId)
            return .hit(
                actualLocation: GeoPoint(latitude: actualCoord.latitude, longitude: actualCoord.longitude),
                distance: closestDistance,
                targetName: targetName
            )
        } else {
            // Give a temporary safe base (expires midnight) to the closest active opponent
            let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
            let closestOpponentId = game.players
                .filter { $0.key != fromUserId && $0.value.isActive }
                .compactMap { (key, _) -> (String, Double)? in
                    guard let coord = game.players[key]?.homeBase else { return nil }
                    let d = guessedCL.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                    return (key, d)
                }
                .min { $0.1 < $1.1 }
                .map { $0.0 }

            if let opponentId = closestOpponentId, var opponentState = game.players[opponentId] {
                let tempBase = SafeBase(
                    id: UUID().uuidString,
                    location: guessedLocation,
                    createdAt: Date(),
                    type: .missedTag,
                    expiresAt: midnight
                )
                opponentState.safeBases.append(tempBase)
                await updatePlayerState(gameId: gameId, userId: opponentId, state: opponentState)
            }

            return .miss(distance: closestDistance == .greatestFiniteMagnitude ? 9999 : closestDistance)
        }
    }

    // MARK: - Arsenal

    func decrementItem(gameId: String, userId: String, item: ArsenalItem) {
        Task {
            guard let game = await fetchGame(by: gameId),
                  var state = game.players[userId] else { return }
            switch item {
            case .basicTag:
                if state.tagsRemainingToday > 0 { state.tagsRemainingToday -= 1 }
                else { state.purchasedTags.extraBasicTags -= 1 }
            case .wideRadiusTag: state.purchasedTags.wideRadiusTags -= 1
            case .radar:         state.purchasedTags.radars -= 1
            case .tripwire:      state.purchasedTags.tripwires -= 1
            }
            await updatePlayerState(gameId: gameId, userId: userId, state: state)
        }
    }

    func useRadar(gameId: String, userId: String) {
        decrementItem(gameId: gameId, userId: userId, item: .radar)
    }

    func placeTripwire(gameId: String, userId: String, tripwire: Tripwire) {
        Task {
            guard let game = await fetchGame(by: gameId),
                  var state = game.players[userId] else { return }
            state.tripwires.append(tripwire)
            state.purchasedTags.tripwires -= 1
            await updatePlayerState(gameId: gameId, userId: userId, state: state)
        }
    }

    func purchaseItem(userId: String, product: StoreProduct) async {
        let games = await fetchGames(for: userId)
        for game in games where game.status != .completed {
            guard var state = game.players[userId] else { continue }
            switch product.item {
            case .basicTag:     state.purchasedTags.extraBasicTags += product.quantity
            case .wideRadiusTag: state.purchasedTags.wideRadiusTags += product.quantity
            case .radar:        state.purchasedTags.radars += product.quantity
            case .tripwire:     state.purchasedTags.tripwires += product.quantity
            }
            await updatePlayerState(gameId: game.id, userId: userId, state: state)
        }
    }

    func resetDailyTagsIfNeeded(gameId: String, userId: String) {
        Task {
            guard let game = await fetchGame(by: gameId),
                  var state = game.players[userId] else { return }
            let today = Calendar.current.startOfDay(for: Date())
            let lastReset = Calendar.current.startOfDay(for: state.lastTagResetDate)
            guard today > lastReset else { return }
            state.tagsRemainingToday = GameConstants.dailyTagLimit
            state.lastTagResetDate = Date()
            state.safeBases.removeAll { sb in
                guard let exp = sb.expiresAt else { return false }
                return Date() >= exp
            }
            await updatePlayerState(gameId: gameId, userId: userId, state: state)
        }
    }

    // MARK: - Private Helpers

    private func fetchPlayerLocation(userId: String) async -> CLLocationCoordinate2D? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.locations)
                .child(userId)
                .child("current")
                .getData()
            guard snapshot.exists(), let dict = snapshot.value as? [String: Any],
                  let lat = dict["latitude"] as? Double,
                  let lng = dict["longitude"] as? Double else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } catch {
            return nil
        }
    }

    private func fetchDisplayName(userId: String) async -> String {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.users)
                .child(userId)
                .child("displayName")
                .getData()
            return snapshot.value as? String ?? "Player"
        } catch {
            return "Player"
        }
    }

    private func activateIfReady(gameId: String) async {
        guard let game = await fetchGame(by: gameId), game.status == .waiting else { return }
        let allReady = game.players.values.allSatisfy { $0.homeBase != nil }
        guard allReady else { return }
        do {
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(gameId)
                .child("status")
                .setValue(GameStatus.active.rawValue)
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(gameId)
                .child("startedAt")
                .setValue(ServerValue.timestamp())
        } catch {}
    }

    private func checkAndCompleteGame(gameId: String) async {
        guard let game = await fetchGame(by: gameId) else { return }
        let activePlayers = game.players.values.filter(\.isActive)
        guard activePlayers.count <= 1 else { return }
        do {
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(gameId)
                .child("status")
                .setValue(GameStatus.completed.rawValue)
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(gameId)
                .child("endedAt")
                .setValue(ServerValue.timestamp())
        } catch {}
    }

    private func appendGameId(_ gameId: String, toUser userId: String) async throws {
        let ref = database
            .child(GameConstants.FirebasePath.users)
            .child(userId)
            .child("activeGameIds")
        let snapshot = try await ref.getData()
        var ids = (snapshot.value as? [String]) ?? []
        guard !ids.contains(gameId) else { return }
        ids.append(gameId)
        try await ref.setValue(ids)
    }

    private func removeGameId(_ gameId: String, fromUser userId: String) async throws {
        let ref = database
            .child(GameConstants.FirebasePath.users)
            .child(userId)
            .child("activeGameIds")
        let snapshot = try await ref.getData()
        var ids = (snapshot.value as? [String]) ?? []
        ids.removeAll { $0 == gameId }
        try await ref.setValue(ids.isEmpty ? NSNull() : ids as Any)
    }

    // MARK: - Serialization

    private func encodeGame(_ game: Game) throws -> [String: Any] {
        let data = try fbEncoder.encode(game)
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Serialization", code: 0)
        }
        dict.removeValue(forKey: "id") // id is the Firebase key, not a field
        return dict
    }

    private func decodeGame(id: String, from value: Any) throws -> Game {
        var dict = value as? [String: Any] ?? [:]
        dict["id"] = id  // inject the key as the id field
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try fbDecoder.decode(Game.self, from: data)
    }

    private static func generateCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<GameConstants.registrationCodeLength).map { _ in chars.randomElement()! })
    }
}

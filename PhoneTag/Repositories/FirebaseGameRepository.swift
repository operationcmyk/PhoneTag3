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

    /// Weak reference to LocationService so tripwire processing can remove consumed geofences.
    /// Set by ContentView after both objects are created.
    weak var locationService: LocationService?

    // MARK: - Fetch

    func fetchGames(for userId: String) async -> [Game] {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.users)
                .child(userId)
                .child("activeGameIds")
                .getData()

            print("🔍 [fetchGames] userId=\(userId)")
            print("🔍 [fetchGames] snapshot exists=\(snapshot.exists()), raw value=\(String(describing: snapshot.value))")

            var gameIds = Self.parseStringArray(snapshot.value)
            print("🔍 [fetchGames] parsed gameIds=\(gameIds)")

            // Fallback: if no gameIds found in user node, scan all games for this player
            if gameIds.isEmpty {
                print("🔍 [fetchGames] no activeGameIds — scanning all games for userId=\(userId)")
                gameIds = await scanAllGames(forUserId: userId)
                print("🔍 [fetchGames] scan found gameIds=\(gameIds)")

                // Backfill the user's activeGameIds so future fetches are fast
                if !gameIds.isEmpty {
                    let ref = database
                        .child(GameConstants.FirebasePath.users)
                        .child(userId)
                        .child("activeGameIds")
                    try? await ref.setValue(gameIds)
                    print("✅ [fetchGames] backfilled activeGameIds for userId=\(userId)")
                }
            }

            var games: [Game] = []
            for gameId in gameIds {
                if let game = await fetchGame(by: gameId) {
                    games.append(game)
                    print("✅ [fetchGames] loaded game id=\(gameId) title=\(game.title)")
                } else {
                    print("❌ [fetchGames] failed to load game id=\(gameId)")
                }
            }
            return games
        } catch {
            print("❌ [fetchGames] error=\(error)")
            return []
        }
    }

    /// Scans every game in /games and returns IDs of games where `userId` appears in `players`.
    /// This is a fallback for when a user's `activeGameIds` node is missing.
    private func scanAllGames(forUserId userId: String) async -> [String] {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.games)
                .getData()
            guard snapshot.exists(), let allGames = snapshot.value as? [String: Any] else {
                return []
            }
            var found: [String] = []
            for (gameId, gameValue) in allGames {
                guard let gameDict = gameValue as? [String: Any],
                      let players = gameDict["players"] as? [String: Any],
                      players[userId] != nil else { continue }
                // Skip completed games that are very old — optional, keep all for now
                found.append(gameId)
            }
            return found
        } catch {
            print("❌ [scanAllGames] error=\(error)")
            return []
        }
    }

    func fetchGame(by id: String) async -> Game? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.games)
                .child(id)
                .getData()
            guard snapshot.exists(), let value = snapshot.value else {
                print("❌ [fetchGame] id=\(id) snapshot missing or nil")
                return nil
            }
            let game = try decodeGame(id: id, from: value)
            return game
        } catch {
            print("❌ [fetchGame] id=\(id) decode error=\(error)")
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

            // Store reverse-lookup index so joinGame can find game by code without a query index
            try await database
                .child(GameConstants.FirebasePath.registrationCodes)
                .child(game.registrationCode)
                .setValue(gameId)

            // Add this gameId to every player's activeGameIds list
            for pid in allPlayerIds {
                try await appendGameId(gameId, toUser: pid)
            }

            // Notify invited players (existing users who have an FCM token)
            let creatorName = await fetchDisplayName(userId: createdBy)
            await NotificationService.shared.sendGameInviteNotifications(
                gameId: gameId,
                gameTitle: title,
                invitedByName: creatorName,
                playerIds: allPlayerIds,
                creatorId: createdBy
            )
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

        let guessedCL = CLLocation(latitude: guessedLocation.latitude, longitude: guessedLocation.longitude)
        let tagRadius = tagType == .basic ? GameConstants.basicTagRadius : GameConstants.wideRadiusTagRadius

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

        // Self-bomb: if the guess lands on the tagger's own location, they take the hit themselves.
        if let taggerCoord = await fetchPlayerLocation(userId: fromUserId) {
            let taggerCL = CLLocation(latitude: taggerCoord.latitude, longitude: taggerCoord.longitude)
            if guessedCL.distance(from: taggerCL) <= tagRadius {
                taggerState.strikes = max(0, taggerState.strikes - 1)
                if taggerState.strikes == 0 { taggerState.isActive = false }

                let taggerName = await fetchDisplayName(userId: fromUserId)
                let permanentBase = SafeBase(
                    id: UUID().uuidString,
                    location: taggerCoord,
                    createdAt: Date(),
                    type: .hitTag,
                    expiresAt: nil,
                    radius: GameConstants.basicTagRadius,
                    taggerName: taggerName,
                    targetName: taggerName
                )
                taggerState.safeBases.append(permanentBase)
                await updatePlayerState(gameId: gameId, userId: fromUserId, state: taggerState)
                await checkAndCompleteGame(gameId: gameId)

                let allPlayerIds = Array(game.players.keys)
                if taggerState.strikes == 0 {
                    Task {
                        await NotificationService.shared.sendEliminationNotification(
                            gameId: gameId,
                            gameTitle: game.title,
                            eliminatedPlayerName: taggerName,
                            playerIds: allPlayerIds,
                            eliminatedId: fromUserId
                        )
                    }
                } else {
                    Task {
                        await NotificationService.shared.sendHitNotification(
                            to: fromUserId,
                            taggerName: taggerName,
                            tagType: tagType,
                            gameId: gameId,
                            gameTitle: game.title
                        )
                    }
                }

                return .hit(
                    actualLocation: GeoPoint(latitude: taggerCoord.latitude, longitude: taggerCoord.longitude),
                    distance: 0,
                    targetName: taggerName
                )
            }
        }

        // Block if the tagger is trying to re-tag a location they already missed in the last 24h.
        // Miss safe bases are stored on opponent states but tagged with the tagger's userId.
        let allMisses = game.players.values.flatMap { $0.safeBases }
            .filter { $0.type == .missedTag && $0.taggerUserId == fromUserId }
        let isDuplicate = allMisses.contains { miss in
            let missLocation = CLLocation(latitude: miss.location.latitude, longitude: miss.location.longitude)
            return guessedCL.distance(from: missLocation) <= miss.effectiveRadius
        }
        if isDuplicate { return .blocked(reason: .duplicateLocation) }

        var closestDistance = Double.greatestFiniteMagnitude
        var hitPlayerId: String?

        let taggerName = await fetchDisplayName(userId: fromUserId)

        for (playerId, playerState) in game.players where playerId != fromUserId && playerState.isActive {
            guard let actualCoord = await fetchPlayerLocation(userId: playerId) else { continue }
            let actualCL = CLLocation(latitude: actualCoord.latitude, longitude: actualCoord.longitude)
            let distance = guessedCL.distance(from: actualCL)
            if distance < closestDistance { closestDistance = distance }

            // Warn player if the tag landed within 1500ft (~457m) of their actual location,
            // regardless of whether it's a hit or miss.
            if distance <= GameConstants.tagWarningRadius {
                Task {
                    await NotificationService.shared.sendTagWarningNotification(
                        to: playerId,
                        taggerName: taggerName,
                        gameTitle: game.title
                    )
                }
            }

            guard distance <= tagRadius else { continue }

            // Check home bases (target's own home bases)
            let isAtHomeBase = [playerState.homeBase1, playerState.homeBase2]
                .compactMap { $0 }
                .contains { hb in
                    actualCL.distance(from: CLLocation(latitude: hb.latitude, longitude: hb.longitude))
                        <= GameConstants.homeBaseRadius
                }
            if isAtHomeBase { return .blocked(reason: .homeBase) }

            // Rule: A player cannot be tagged in ANY safe zone on the map — theirs OR anyone else's.
            // Collect every safe base from every player in the game.
            let allSafeBases = game.players.values.flatMap { $0.safeBases }
            let isAtSafeBase = allSafeBases.contains { sb in
                actualCL.distance(from: CLLocation(latitude: sb.location.latitude, longitude: sb.location.longitude))
                    <= sb.effectiveRadius
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

            let targetName = await fetchDisplayName(userId: hitId)

            // Rule: Hit safe zone is always basic-tag-sized (80m), regardless of weapon used.
            let permanentBase = SafeBase(
                id: UUID().uuidString,
                location: actualCoord,
                createdAt: Date(),
                type: .hitTag,
                expiresAt: nil,
                radius: GameConstants.basicTagRadius,
                taggerName: taggerName,
                targetName: targetName
            )
            targetState.safeBases.append(permanentBase)
            await updatePlayerState(gameId: gameId, userId: hitId, state: targetState)
            await checkAndCompleteGame(gameId: gameId)

            // Notify the hit player (or all others on elimination)
            let allPlayerIds = Array(game.players.keys)
            if targetState.strikes == 0 {
                // Player eliminated — notify everyone else
                Task {
                    await NotificationService.shared.sendEliminationNotification(
                        gameId: gameId,
                        gameTitle: game.title,
                        eliminatedPlayerName: targetName,
                        playerIds: allPlayerIds,
                        eliminatedId: hitId
                    )
                }
            } else {
                // Player hit but still alive — notify them only
                Task {
                    await NotificationService.shared.sendHitNotification(
                        to: hitId,
                        taggerName: taggerName,
                        tagType: tagType,
                        gameId: gameId,
                        gameTitle: game.title
                    )
                }
            }

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
                    expiresAt: midnight,
                    radius: GameConstants.safeBaseRadius,
                    taggerName: nil,
                    taggerUserId: fromUserId
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

    // MARK: - Inactivity Strike Deduction

    func deductStrikeForInactivity(gameId: String, userId: String) async -> (playerName: String, wasEliminated: Bool)? {
        guard let game = await fetchGame(by: gameId),
              game.status == .active,
              var state = game.players[userId],
              state.isActive,
              state.strikes > 0 else { return nil }

        state.strikes = max(0, state.strikes - 1)
        if state.strikes == 0 { state.isActive = false }

        await updatePlayerState(gameId: gameId, userId: userId, state: state)

        if state.strikes == 0 {
            await checkAndCompleteGame(gameId: gameId)
        }

        let playerName = await fetchDisplayName(userId: userId)
        return (playerName: playerName, wasEliminated: state.strikes == 0)
    }

    // MARK: - Nudge Deadline

    func setNudgeDeadline(gameId: String) async {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let deadlineMs = nowMs + GameConstants.nudgeResponseWindow * 1000
        do {
            let gameRef = database.child(GameConstants.FirebasePath.games).child(gameId)
            try await gameRef.child("nudgeIssuedAt").setValue(nowMs)
            try await gameRef.child("nudgeDeadlineAt").setValue(deadlineMs)
        } catch {
            print("❌ [FirebaseGameRepository] Failed to set nudge deadline: \(error)")
        }
    }

    func clearNudgeDeadline(gameId: String) async {
        do {
            let gameRef = database.child(GameConstants.FirebasePath.games).child(gameId)
            try await gameRef.child("nudgeIssuedAt").setValue(NSNull())
            try await gameRef.child("nudgeDeadlineAt").setValue(NSNull())
        } catch {
            print("❌ [FirebaseGameRepository] Failed to clear nudge deadline: \(error)")
        }
    }

    // MARK: - Tripwire Hit

    func processTripwireHit(tripwireId: String, gameId: String, triggeredByUserId: String) async -> TagResult? {
        guard let game = await fetchGame(by: gameId),
              game.status == .active else { return nil }

        // Find the player who placed this tripwire
        guard let (placerUserId, _) = game.players.first(where: { _, state in
            state.tripwires.contains(where: { $0.id == tripwireId })
        }),
        let tripwire = game.players[placerUserId]?.tripwires.first(where: { $0.id == tripwireId }),
        let tripwireCenter = tripwire.path.first else { return nil }

        // The triggered user must still be active
        guard var triggeredState = game.players[triggeredByUserId],
              triggeredState.isActive,
              triggeredState.strikes > 0 else { return nil }

        // Deduct strike from the triggered player
        let previousStrikes = triggeredState.strikes
        triggeredState.strikes = max(0, triggeredState.strikes - 1)
        if triggeredState.strikes == 0 { triggeredState.isActive = false }

        let triggeredName = await fetchDisplayName(userId: triggeredByUserId)
        let placerName = await fetchDisplayName(userId: placerUserId)

        // Create a permanent safe zone at the tripwire location (basic-tag-sized, same rules as a hit)
        let permanentBase = SafeBase(
            id: UUID().uuidString,
            location: tripwireCenter,
            createdAt: Date(),
            type: .hitTag,
            expiresAt: nil,
            radius: GameConstants.basicTagRadius,
            taggerName: placerName,
            targetName: triggeredName
        )
        triggeredState.safeBases.append(permanentBase)
        await updatePlayerState(gameId: gameId, userId: triggeredByUserId, state: triggeredState)

        // Remove the tripwire from the placer's state
        if var placerState = game.players[placerUserId] {
            placerState.tripwires.removeAll { $0.id == tripwireId }
            await updatePlayerState(gameId: gameId, userId: placerUserId, state: placerState)
        }

        // Remove the geofence (it's now consumed)
        locationService?.removeGeofence(identifier: tripwireId)
        let allPlayerIds = Array(game.players.keys)

        if triggeredState.strikes == 0 {
            await checkAndCompleteGame(gameId: gameId)
            Task {
                await NotificationService.shared.sendEliminationNotification(
                    gameId: gameId,
                    gameTitle: game.title,
                    eliminatedPlayerName: triggeredName,
                    playerIds: allPlayerIds,
                    eliminatedId: triggeredByUserId
                )
            }
        } else {
            Task {
                await NotificationService.shared.sendHitNotification(
                    to: triggeredByUserId,
                    taggerName: "\(placerName)'s Tripwire",
                    tagType: .basic,
                    gameId: gameId,
                    gameTitle: game.title
                )
            }
        }

        let hitCoord = GeoPoint(latitude: tripwireCenter.latitude, longitude: tripwireCenter.longitude)
        return .hit(actualLocation: hitCoord, distance: 0, targetName: triggeredName)
    }

    // MARK: - Join by Code

    func joinGame(byCode code: String, userId: String) async -> Game? {
        do {
            // Direct key lookup — no Firebase index required
            let codeSnapshot = try await database
                .child(GameConstants.FirebasePath.registrationCodes)
                .child(code.uppercased())
                .getData()
            guard codeSnapshot.exists(), let gameId = codeSnapshot.value as? String else { return nil }

            guard var game = await fetchGame(by: gameId) else { return nil }

            // Already a player — just surface the game
            if game.players[userId] != nil {
                try await appendGameId(gameId, toUser: userId)
                return game
            }

            // Game must still be in waiting state to accept new players
            guard game.status == .waiting else { return nil }

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
            game.players[userId] = newState

            let playerData = try fbEncoder.encode(newState)
            let playerDict = try JSONSerialization.jsonObject(with: playerData) as? [String: Any] ?? [:]
            try await database
                .child(GameConstants.FirebasePath.games)
                .child(gameId)
                .child("players")
                .child(userId)
                .setValue(playerDict)

            try await appendGameId(gameId, toUser: userId)
            return game
        } catch {
            return nil
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
        // All players must have placed BOTH safe zones before the game goes active
        let allReady = game.players.values.allSatisfy { $0.hasBothSafeZones }
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

            // Notify all players the game has begun
            let allPlayerIds = Array(game.players.keys)
            Task {
                await NotificationService.shared.sendGameStartedNotification(
                    gameId: gameId,
                    gameTitle: game.title,
                    playerIds: allPlayerIds
                )
            }
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
        var ids = Self.parseStringArray(snapshot.value)
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
        var ids = Self.parseStringArray(snapshot.value)
        ids.removeAll { $0 == gameId }
        try await ref.setValue(ids.isEmpty ? NSNull() : ids as Any)
    }

    /// Handles both a true JSON array ([String]) and Firebase's dict-of-indices (["0": "id1", "1": "id2"])
    private static func parseStringArray(_ value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
        }
        if let dict = value as? [String: Any] {
            // Sort by numeric key so order is preserved
            return dict
                .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
                .compactMap { $0.value as? String }
        }
        return []
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

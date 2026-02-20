import Foundation
import CoreLocation
@preconcurrency import FirebaseDatabase

/// Session-level location uploader. Lives as long as the user is authenticated,
/// completely independent of which screen is visible or whether a game is active.
///
/// Strategy:
/// - Foreground: uploads on every CLLocation update (throttled to 5 min)
/// - Background: significant-location-change wakes the app; we upload immediately
/// - No active game: still uploads so the location is fresh when a tag is submitted
///
/// Offline penalty rules:
/// - 47h offline  → send the offline player a personal warning push notification
/// - 48h offline  → deduct 1 strike from the player in every active game, notify all co-players
/// - On return    → notify all co-players that the player is back
@MainActor
final class UserLocationManager: ObservableObject {

    private let locationService: LocationService
    private let locationRepository = LocationRepository()
    private let gameRepository: GameRepositoryProtocol
    private var userId: String?
    private var uploadTask: Task<Void, Never>?
    private var offlineCheckTask: Task<Void, Never>?

    // Offline thresholds in milliseconds
    private static let warningThresholdMs: Double  = 47 * 3_600_000   // 47 hours
    private static let penaltyThresholdMs: Double  = 48 * 3_600_000   // 48 hours

    // How often to poll for co-player offline status (every 30 minutes)
    private static let offlineCheckIntervalSec: TimeInterval = 1_800

    init(locationService: LocationService, gameRepository: GameRepositoryProtocol) {
        self.locationService = locationService
        self.gameRepository = gameRepository
    }

    // MARK: - Session Lifecycle

    /// Call when the user authenticates. Starts location tracking and uploading.
    func start(userId: String) {
        self.userId = userId
        locationService.requestWhenInUseAuthorization()
        locationService.startUpdatingLocation()
        locationService.startMonitoringSignificantChanges()
        startUploadLoop()
        startOfflineCheckLoop(userId: userId)
    }

    /// Call when the user signs out or the session ends.
    func stop() {
        userId = nil
        uploadTask?.cancel()
        uploadTask = nil
        offlineCheckTask?.cancel()
        offlineCheckTask = nil
        locationService.stopUpdatingLocation()
        locationService.stopMonitoringSignificantChanges()
    }

    // MARK: - Upload on Location Change

    /// Called by the view layer whenever `locationService.locationUpdateCount` changes.
    /// Uploads immediately (throttled) so significant-change wakeups reach Firebase fast.
    func onLocationUpdate() {
        guard userId != nil else { return }
        Task { await uploadNow() }
    }

    // MARK: - Private Upload

    /// Periodic fallback loop — ensures location is uploaded at least every 5 minutes
    /// even if the OS doesn't fire a significant-change event.
    private func startUploadLoop() {
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.uploadNow()
                try? await Task.sleep(for: .seconds(GameConstants.backgroundLocationUpdateInterval))
            }
        }
    }

    private func uploadNow() async {
        guard let userId,
              let location = locationService.currentLocation,
              locationService.shouldUploadLocation() else { return }

        // Read the previous upload timestamp BEFORE writing the new one,
        // so we can determine whether the user was "offline" for 48+ hours on their return.
        let previousUploadMs = await locationRepository.fetchLastUploadedAt(userId: userId)

        do {
            try await locationRepository.uploadLocation(userId: userId, location: location)
            locationService.didUploadLocation()
            print("📍 [UserLocationManager] Location uploaded for userId=\(userId)")
        } catch {
            print("❌ [UserLocationManager] Upload failed: \(error)")
            return
        }

        // On return: if gap was 48h+ notify co-players; if 24h+ also announce return.
        let nowMs = Date().timeIntervalSince1970 * 1000
        let gapMs = nowMs - (previousUploadMs ?? nowMs)
        if gapMs > Self.penaltyThresholdMs {
            print("👀 [UserLocationManager] User \(userId) returned after \(Int(gapMs / 3_600_000))h — notifying co-players of return.")
            Task { await notifyReturnedInAllGames(userId: userId) }
        } else if gapMs > Self.warningThresholdMs {
            // Between 47-48h offline: just notify of return (warning was already sent by the check loop)
            Task { await notifyReturnedInAllGames(userId: userId) }
        }
    }

    // MARK: - Offline Check Loop (runs on-device while app is in foreground/background)

    /// Runs every 30 minutes while the session is active.
    /// Checks every co-player's `lastUploadedAt` in every active game:
    ///   - At 47h: sends the offline player a personal warning push notification
    ///   - At 48h+: deducts a strike and notifies all players
    private func startOfflineCheckLoop(userId: String) {
        offlineCheckTask?.cancel()
        offlineCheckTask = Task { [weak self] in
            // First check runs after a short delay so game data is loaded
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.checkCoPlayersForInactivity(currentUserId: userId)
                try? await Task.sleep(for: .seconds(Self.offlineCheckIntervalSec))
            }
        }
    }

    private func checkCoPlayersForInactivity(currentUserId: String) async {
        let games = await gameRepository.fetchGames(for: currentUserId)
        let activeGames = games.filter { $0.status == .active }
        guard !activeGames.isEmpty else { return }

        let nowMs = Date().timeIntervalSince1970 * 1000

        for game in activeGames {
            let activePlayers = game.players.filter { $0.value.isActive }.map { $0.key }

            for playerId in activePlayers where playerId != currentUserId {
                guard let lastUploadMs = await locationRepository.fetchLastUploadedAt(userId: playerId) else {
                    continue  // Player has never uploaded — no data to act on
                }

                let gapMs = nowMs - lastUploadMs
                let gapHours = Int(gapMs / 3_600_000)

                if gapMs >= Self.penaltyThresholdMs {
                    // 48h+ offline — deduct a strike
                    print("⚠️ [UserLocationManager] Player \(playerId) offline \(gapHours)h — deducting strike in game \(game.id)")
                    if let result = await gameRepository.deductStrikeForInactivity(gameId: game.id, userId: playerId) {
                        let allPlayerIds = game.players.map { $0.key }
                        if result.wasEliminated {
                            await NotificationService.shared.sendEliminationNotification(
                                gameId: game.id,
                                gameTitle: game.title,
                                eliminatedPlayerName: result.playerName,
                                playerIds: allPlayerIds,
                                eliminatedId: playerId
                            )
                        } else {
                            await NotificationService.shared.sendOfflineStrikeLostNotification(
                                offlinePlayerName: result.playerName,
                                gameId: game.id,
                                gameTitle: game.title,
                                playerIds: allPlayerIds,
                                offlinePlayerId: playerId
                            )
                        }
                    }
                } else if gapMs >= Self.warningThresholdMs {
                    // 47h offline — send personal warning to the offline player
                    print("⏰ [UserLocationManager] Player \(playerId) offline \(gapHours)h — sending warning for game \(game.id)")
                    await NotificationService.shared.sendOfflineWarningNotification(
                        to: playerId,
                        gameTitle: game.title,
                        gameId: game.id
                    )
                }
            }
        }
    }

    // MARK: - Return Notification

    /// Sends a "player is back" notification to co-players in every active game.
    private func notifyReturnedInAllGames(userId: String) async {
        let games = await gameRepository.fetchGames(for: userId)
        let activeGames = games.filter { $0.status == .active }
        guard !activeGames.isEmpty else { return }

        let displayName = await fetchDisplayName(userId: userId)

        for game in activeGames {
            let activePlayers = game.players
                .filter { $0.value.isActive }
                .map { $0.key }
            await NotificationService.shared.sendPlayerReturnedNotification(
                gameId: game.id,
                gameTitle: game.title,
                returnedPlayerName: displayName,
                playerIds: activePlayers,
                returnedId: userId
            )
        }
    }

    // MARK: - Helpers

    /// Fetches the display name for a user from Firebase.
    private func fetchDisplayName(userId: String) async -> String {
        do {
            let snapshot = try await FirebaseDatabase.Database.database().reference()
                .child(GameConstants.FirebasePath.users)
                .child(userId)
                .child("displayName")
                .getData()
            return snapshot.value as? String ?? "A player"
        } catch {
            return "A player"
        }
    }
}

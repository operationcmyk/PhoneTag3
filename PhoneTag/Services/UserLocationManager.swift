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
@MainActor
final class UserLocationManager: ObservableObject {

    private let locationService: LocationService
    private let locationRepository = LocationRepository()
    private let gameRepository: GameRepositoryProtocol
    private var userId: String?
    private var uploadTask: Task<Void, Never>?

    private static let twentyFourHoursMs: Double = 86_400_000

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
    }

    /// Call when the user signs out or the session ends.
    func stop() {
        userId = nil
        uploadTask?.cancel()
        uploadTask = nil
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

    // MARK: - Private

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
        // so we can determine whether the user was "offline" for 24+ hours.
        let previousUploadMs = await locationRepository.fetchLastUploadedAt(userId: userId)

        do {
            try await locationRepository.uploadLocation(userId: userId, location: location)
            locationService.didUploadLocation()
            print("📍 [UserLocationManager] Location uploaded for userId=\(userId)")
        } catch {
            print("❌ [UserLocationManager] Upload failed: \(error)")
            return
        }

        // Check if user was offline for more than 24 hours.
        let nowMs = Date().timeIntervalSince1970 * 1000
        let gapMs = nowMs - (previousUploadMs ?? nowMs)
        if gapMs > Self.twentyFourHoursMs {
            print("👀 [UserLocationManager] User \(userId) was offline for \(Int(gapMs / 3_600_000))h — sending return notifications.")
            Task { await notifyReturnedInAllGames(userId: userId) }
        }
    }

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

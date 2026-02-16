import Foundation
import CoreLocation
import MapKit
import SwiftUI

@MainActor
@Observable
final class GameBoardViewModel {
    let userId: String
    let gameRepository: any GameRepositoryProtocol
    let userRepository: any UserRepositoryProtocol
    let locationService: LocationService
    private let locationRepository = LocationRepository()

    var game: Game
    var playerNames: [String: String] = [:] // userId -> displayName
    var cameraPosition: MapCameraPosition = .automatic
    var visibleMapCenter: CLLocationCoordinate2D?
    private var hasCenteredOnUser = false
    private var locationUploadTask: Task<Void, Never>?

    // Home base placement
    var isSettingHomeBase: Bool {
        guard let state = myPlayerState else { return false }
        return state.homeBase == nil
    }

    var tempHomeBase: CLLocationCoordinate2D?

    /// 0 = needs to place, 1 = placed awaiting confirm
    var homeBasePlacementStep: Int {
        if tempHomeBase == nil { return 0 }
        return 1
    }

    // Arsenal & Tagging
    var isArsenalOpen = false
    var selectedArsenalItem: ArsenalItem?
    var isTagging = false
    var tagResult: TagResult?
    var showingTagResult = false
    var isSubmittingTag = false
    var submittedTags: [Tag] = []

    /// Tags that should still be visible on the map.
    /// Hits stay until game ends; misses expire at midnight.
    var visibleTags: [Tag] {
        let now = Date()
        return submittedTags.filter { tag in
            guard let result = tag.result else { return false }
            switch result {
            case .hit:
                return true // permanent until game ends
            case .miss:
                // Visible until end of day (midnight)
                let tagMidnight = Calendar.current.startOfDay(for: tag.timestamp).addingTimeInterval(86400)
                return now < tagMidnight
            case .blocked:
                return false // blocked tags don't show on map
            }
        }
    }

    var myPlayerState: PlayerState? {
        game.players[userId]
    }

    var sortedPlayerIds: [String] {
        // Creator first, then alphabetical; current user always at index 0 visually
        var ids = Array(game.players.keys)
        ids.sort { a, b in
            if a == userId { return true }
            if b == userId { return false }
            return a < b
        }
        return ids
    }

    init(game: Game, userId: String, gameRepository: any GameRepositoryProtocol, userRepository: any UserRepositoryProtocol, locationService: LocationService) {
        self.game = game
        self.userId = userId
        self.gameRepository = gameRepository
        self.userRepository = userRepository
        self.locationService = locationService
    }

    func loadPlayerNames() async {
        for playerId in game.players.keys {
            if let user = await userRepository.fetchUser(playerId) {
                playerNames[playerId] = user.displayName
            }
        }
    }

    func placeHomeBase(at coordinate: CLLocationCoordinate2D) {
        if tempHomeBase == nil {
            tempHomeBase = coordinate
        }
    }

    func undoPlacement() {
        tempHomeBase = nil
    }

    func saveHomeBase() async {
        guard let base = tempHomeBase,
              var state = myPlayerState else { return }

        state.homeBase = base
        await gameRepository.updatePlayerState(gameId: game.id, userId: userId, state: state)

        if let updated = await gameRepository.fetchGame(by: game.id) {
            game = updated
        }

        tempHomeBase = nil
    }

    // MARK: - Arsenal

    func toggleArsenal() {
        isArsenalOpen.toggle()
        if !isArsenalOpen {
            selectedArsenalItem = nil
        }
    }

    func selectArsenalItem(_ item: ArsenalItem) {
        guard let state = myPlayerState, item.isAvailable(from: state) else { return }
        selectedArsenalItem = item
    }

    /// Called when the user confirms using the selected arsenal item.
    func useSelectedItem() {
        guard let item = selectedArsenalItem else { return }

        switch item {
        case .basicTag, .wideRadiusTag:
            isTagging = true
            isArsenalOpen = false
        case .radar:
            activateRadar()
        case .tripwire:
            placeTripwire()
        }
    }

    // MARK: - Tagging

    func cancelTagging() {
        isTagging = false
        selectedArsenalItem = nil
    }

    func submitTag(at coordinate: CLLocationCoordinate2D) async {
        guard !isSubmittingTag else { return }
        isSubmittingTag = true
        defer { isSubmittingTag = false }

        let tagType: TagType = selectedArsenalItem == .wideRadiusTag ? .wideRadius : .basic

        let result = await gameRepository.submitTag(
            gameId: game.id,
            fromUserId: userId,
            guessedLocation: coordinate,
            tagType: tagType
        )

        // Store the tag for map display
        let tag = Tag(
            id: UUID().uuidString,
            gameId: game.id,
            fromUserId: userId,
            targetUserId: "",
            guessedLocation: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            timestamp: Date(),
            result: result,
            tagType: tagType
        )
        submittedTags.append(tag)

        tagResult = result
        showingTagResult = true
        isTagging = false
        selectedArsenalItem = nil

        if let updated = await gameRepository.fetchGame(by: game.id) {
            game = updated
        }
    }

    // MARK: - Radar

    /// Two-circle radar result: one real (jittered), one decoy.
    var radarResult: RadarResult?
    var showingRadar = false
    var radarTimeRemaining: Int = 0
    private var radarDismissTask: Task<Void, Never>?

    private func activateRadar() {
        guard let state = myPlayerState, state.purchasedTags.radars > 0 else { return }

        gameRepository.useRadar(gameId: game.id, userId: userId)

        // Build radar result from mock data (production would call a Cloud Function)
        if let repo = gameRepository as? MockGameRepository {
            let opponents = game.players.filter { $0.key != userId && $0.value.isActive }
            if let opponentId = opponents.keys.randomElement(),
               let actualCoord = repo.playerLocations[opponentId] {

                let targetName = playerNames[opponentId] ?? "Unknown"
                let result = Self.buildRadarResult(actualLocation: actualCoord, targetName: targetName)
                radarResult = result
                showingRadar = true
                radarTimeRemaining = Int(GameConstants.radarDuration)

                // Pan camera to fit both circles
                fitCameraToRadar(result)

                // Countdown and auto-dismiss
                radarDismissTask?.cancel()
                radarDismissTask = Task {
                    for _ in 0..<Int(GameConstants.radarDuration) {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        radarTimeRemaining -= 1
                    }
                    showingRadar = false
                    radarResult = nil
                }
            }
        }

        isArsenalOpen = false
        selectedArsenalItem = nil

        Task {
            if let updated = await gameRepository.fetchGame(by: game.id) {
                game = updated
            }
        }
    }

    func dismissRadar() {
        radarDismissTask?.cancel()
        showingRadar = false
        radarResult = nil
    }

    /// Adjust the map camera so both radar circles are fully visible.
    private func fitCameraToRadar(_ radar: RadarResult) {
        guard radar.locations.count == 2 else { return }
        let a = radar.locations[0]
        let b = radar.locations[1]

        // Center between the two circles
        let centerLat = (a.latitude + b.latitude) / 2
        let centerLon = (a.longitude + b.longitude) / 2

        // Span needs to cover both circles plus their radius on each edge.
        // Convert radar radius to approximate degrees for padding.
        let radiusDegLat = radar.radius / 111_320 // ~meters per degree latitude
        let radiusDegLon = radar.radius / (111_320 * cos(centerLat * .pi / 180))

        let latDelta = abs(a.latitude - b.latitude) + radiusDegLat * 3
        let lonDelta = abs(a.longitude - b.longitude) + radiusDegLon * 3

        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }

    /// Build two candidate circles: one near real location, one decoy.
    static func buildRadarResult(actualLocation: CLLocationCoordinate2D, targetName: String) -> RadarResult {
        // Circle A: real location offset by random jitter (stays within radar radius)
        let jitterDistance = Double.random(in: 0...GameConstants.radarJitter)
        let jitterBearing = Double.random(in: 0..<360)
        let realCircleCenter = offsetCoordinate(actualLocation, distanceMeters: jitterDistance, bearingDegrees: jitterBearing)

        // Circle B: decoy placed 1.5–3km away in a random direction
        let decoyDistance = Double.random(in: GameConstants.radarDecoyMinDistance...GameConstants.radarDecoyMaxDistance)
        let decoyBearing = Double.random(in: 0..<360)
        let decoyCenter = offsetCoordinate(actualLocation, distanceMeters: decoyDistance, bearingDegrees: decoyBearing)

        // Shuffle so the user can't assume order
        let locations: [CLLocationCoordinate2D] = Bool.random()
            ? [realCircleCenter, decoyCenter]
            : [decoyCenter, realCircleCenter]

        return RadarResult(
            locations: locations,
            radius: GameConstants.radarRadius,
            targetName: targetName
        )
    }

    /// Offset a coordinate by a distance (meters) at a bearing (degrees).
    private static func offsetCoordinate(
        _ coord: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0 // meters
        let lat1 = coord.latitude * .pi / 180
        let lon1 = coord.longitude * .pi / 180
        let bearing = bearingDegrees * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    // MARK: - Tripwire

    private func placeTripwire() {
        guard let location = locationService.currentLocation,
              let state = myPlayerState,
              state.purchasedTags.tripwires > 0 else { return }

        let tripwire = Tripwire(
            id: UUID().uuidString,
            placedBy: userId,
            gameId: game.id,
            path: [location.coordinate],
            placedAt: Date(),
            triggeredBy: nil,
            triggeredAt: nil,
            isPermanent: false
        )

        gameRepository.placeTripwire(gameId: game.id, userId: userId, tripwire: tripwire)

        isArsenalOpen = false
        selectedArsenalItem = nil

        Task {
            if let updated = await gameRepository.fetchGame(by: game.id) {
                game = updated
            }
        }
    }

    private func findGameIndex() -> Int? {
        // Only used internally for mock updates
        return nil
    }

    func refreshGame() async {
        if let updated = await gameRepository.fetchGame(by: game.id) {
            game = updated
        }
    }

    // MARK: - Location

    /// Called when the game board appears. Starts location updates and
    /// centers the map on the user's current position.
    func onAppear() {
        if locationService.hasLocationPermission {
            locationService.startUpdatingLocation()
        }

        if game.status == .active {
            locationService.startGameTracking()
            startPeriodicLocationUpload()
        }
    }

    /// Called when the game board disappears. Stops foreground-only updates
    /// but keeps background monitoring if the game is active.
    func onDisappear() {
        if game.status != .active {
            locationService.stopUpdatingLocation()
        }
        locationUploadTask?.cancel()
        locationUploadTask = nil
    }

    /// Upload current location to Firebase immediately (if throttle allows).
    func uploadLocationNow() async {
        guard let location = locationService.currentLocation,
              locationService.shouldUploadLocation() else { return }

        do {
            try await locationRepository.uploadLocation(userId: userId, location: location)
            locationService.didUploadLocation()
        } catch {
            // Silently fail — next interval will retry
        }
    }

    /// Start a repeating task that uploads location every 5 minutes.
    private func startPeriodicLocationUpload() {
        locationUploadTask?.cancel()
        locationUploadTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.uploadLocationNow()
                try? await Task.sleep(for: .seconds(GameConstants.backgroundLocationUpdateInterval))
            }
        }
    }

    /// Center the map camera on the user's current location once.
    func centerOnUserIfNeeded() {
        guard !hasCenteredOnUser,
              let location = locationService.currentLocation else { return }
        hasCenteredOnUser = true
        cameraPosition = .region(MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.007, longitudeDelta: 0.007)
        ))
    }

    /// Set up geofences for all tripwires in the current game that target this user.
    func setupTripwireGeofences() {
        guard game.status == .active else { return }

        locationService.removeAllGeofences()

        for (playerId, playerState) in game.players where playerId != userId {
            for tripwire in playerState.tripwires where tripwire.triggeredBy == nil {
                // Use the midpoint of the tripwire path as the geofence center
                guard let center = tripwire.path.first else { continue }
                locationService.addGeofence(
                    identifier: tripwire.id,
                    center: center,
                    radius: GameConstants.tripwireRadius
                )
            }
        }
    }
}

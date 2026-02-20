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

    var game: Game
    var playerNames: [String: String] = [:] // userId -> displayName
    var cameraPosition: MapCameraPosition = .automatic
    var visibleMapCenter: CLLocationCoordinate2D?
    private var hasCenteredOnUser = false

    // Safe zone placement (two required before game can start)
    /// True when the player still needs to place one or both safe zones.
    var isSettingHomeBase: Bool {
        guard let state = myPlayerState else { return false }
        return !state.hasBothSafeZones
    }

    /// Which safe zone is currently being placed (1 or 2).
    var safeZonePlacementNumber: Int {
        guard let state = myPlayerState else { return 1 }
        return state.homeBase1 == nil ? 1 : 2
    }

    /// Temporary pin the player has dropped but not yet confirmed.
    var tempHomeBase: CLLocationCoordinate2D?

    /// Whether the player has dropped a pin for the current step.
    var hasDroppedTempPin: Bool { tempHomeBase != nil }

    // Arsenal & Tagging
    var didLeave = false
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

    /// Maps each player ID to their assigned color, consistent with the bottom bar hearts.
    var playerColorMap: [String: Color] {
        var map: [String: Color] = [:]
        for (index, playerId) in sortedPlayerIds.enumerated() {
            map[playerId] = GameConstants.playerColors[index % GameConstants.playerColors.count]
        }
        return map
    }

    /// The current user's assigned color.
    var myColor: Color {
        playerColorMap[userId] ?? GameConstants.playerColors[0]
    }

    /// All players' safe zones (other than the current user) for map display.
    /// Each player can have up to 2 entries (one per safe zone).
    var otherPlayersHomeBases: [(name: String, coordinate: CLLocationCoordinate2D, color: Color)] {
        var results: [(name: String, coordinate: CLLocationCoordinate2D, color: Color)] = []
        for (playerId, state) in game.players where playerId != userId {
            let name = playerNames[playerId] ?? "Player"
            let color = playerColorMap[playerId] ?? .blue
            if let z1 = state.homeBase1 { results.append((name: "\(name) Zone 1", coordinate: z1, color: color)) }
            if let z2 = state.homeBase2 { results.append((name: "\(name) Zone 2", coordinate: z2, color: color)) }
        }
        return results
    }

    /// The current user's second safe zone (for map display).
    var mySafeZone2: CLLocationCoordinate2D? {
        myPlayerState?.homeBase2
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

    /// Drop a temporary pin at the tapped location for the current safe zone step.
    func placeHomeBase(at coordinate: CLLocationCoordinate2D) {
        tempHomeBase = coordinate
    }

    /// Remove the temporary pin so the player can re-tap a different spot.
    func undoPlacement() {
        tempHomeBase = nil
    }

    /// Confirm and save the temporary pin as safe zone 1 or 2.
    func saveHomeBase() async {
        guard let base = tempHomeBase,
              var state = myPlayerState else { return }

        if state.homeBase1 == nil {
            state.homeBase1 = base
        } else {
            state.homeBase2 = base
        }

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

        isArsenalOpen = false
        selectedArsenalItem = nil

        Task {
            // Pick a random active opponent
            let opponents = game.players.filter { $0.key != userId && $0.value.isActive }
            guard let opponentId = opponents.keys.randomElement() else { return }

            let targetName = playerNames[opponentId] ?? "Player"
            let locationRepo = LocationRepository()
            var actualCoord: CLLocationCoordinate2D?

            // Try Firebase first (production)
            if let loc = try? await locationRepo.fetchLocation(for: opponentId) {
                actualCoord = loc.coordinate
            }
            // Fall back to mock data if available (simulator/testing)
            if actualCoord == nil, let repo = gameRepository as? MockGameRepository {
                actualCoord = repo.playerLocations[opponentId]
            }

            guard let coord = actualCoord else { return }

            let result = Self.buildRadarResult(actualLocation: coord, targetName: targetName)
            radarResult = result
            showingRadar = true
            radarTimeRemaining = Int(GameConstants.radarDuration)

            // Pan camera so both circles are visible
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

    /// Build two candidate circles: one centred on the real location, one decoy.
    /// The real circle is placed exactly on the target — the 61m radius is the ambiguity.
    /// The decoy circle is placed 300–800m away so the viewer can't easily tell which is real.
    static func buildRadarResult(actualLocation: CLLocationCoordinate2D, targetName: String) -> RadarResult {
        // Circle A: real circle — centred exactly on the target's location
        let realCircleCenter = actualLocation

        // Circle B: decoy placed 300–800m away in a random direction
        let decoyDistance = Double.random(in: GameConstants.radarDecoyMinDistance...GameConstants.radarDecoyMaxDistance)
        let decoyBearing = Double.random(in: 0..<360)
        let decoyCenter = offsetCoordinate(actualLocation, distanceMeters: decoyDistance, bearingDegrees: decoyBearing)

        // Shuffle so the tagger can't assume which circle is which
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

    func leaveGame() async {
        await gameRepository.leaveGame(gameId: game.id, userId: userId)
        locationService.stopGameTracking()
        didLeave = true
    }

    func refreshGame() async {
        if let updated = await gameRepository.fetchGame(by: game.id) {
            game = updated
            // Re-sync geofences whenever the game state changes (new tripwires may have been placed).
            if game.status == .active {
                setupTripwireGeofences()
            }
        }
    }

    // MARK: - Location

    /// Called when the game board appears. Starts location updates and
    /// centers the map on the user's current position.
    func onAppear() {
        // Reset daily free tags if a new day has started
        gameRepository.resetDailyTagsIfNeeded(gameId: game.id, userId: userId)
        Task { await refreshGame() }

        if locationService.hasLocationPermission {
            locationService.startUpdatingLocation()
        }

        if game.status == .active {
            locationService.startGameTracking()
            setupTripwireGeofences()
        }
    }

    /// Called when the game board disappears. Stops foreground-only updates
    /// but keeps background monitoring if the game is active.
    func onDisappear() {
        if game.status != .active {
            locationService.stopUpdatingLocation()
        }
        // Location uploading is owned by UserLocationManager at the session level —
        // nothing to cancel here.
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

    /// Called when `locationService.lastTriggeredRegionId` changes.
    /// Processes a tripwire hit: deducts a strike, creates a safe zone, removes the tripwire.
    func handleTripwireTrigger(_ regionId: String) {
        guard game.status == .active else { return }
        Task {
            guard let result = await gameRepository.processTripwireHit(
                tripwireId: regionId,
                gameId: game.id,
                triggeredByUserId: userId
            ) else { return }

            // Show the result in the existing tag result alert
            tagResult = result
            showingTagResult = true

            // Add to the visible tags on the map as a hit marker
            if case .hit(let geo, _, _) = result {
                let coord = CLLocationCoordinate2D(latitude: geo.latitude, longitude: geo.longitude)
                let tag = Tag(
                    id: UUID().uuidString,
                    gameId: game.id,
                    fromUserId: "tripwire",
                    targetUserId: userId,
                    guessedLocation: GeoPoint(latitude: coord.latitude, longitude: coord.longitude),
                    timestamp: Date(),
                    result: result,
                    tagType: .basic
                )
                submittedTags.append(tag)
            }

            // Refresh game state and reset geofences (consumed tripwire is now removed)
            if let updated = await gameRepository.fetchGame(by: game.id) {
                game = updated
                setupTripwireGeofences()
            }
        }
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

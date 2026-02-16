import Foundation
import CoreLocation

@MainActor
@Observable
final class LocationService: NSObject, Sendable {
    // MARK: - Published State

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus
    var locationError: Error?

    /// Incremented on each location update. Use with `.onChange(of:)` since CLLocation isn't Equatable.
    var locationUpdateCount: Int = 0

    // MARK: - Geofence Events

    /// Fired when a monitored region is entered (e.g., tripwire triggered).
    /// Value is the region identifier.
    var lastTriggeredRegionId: String?

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var isUpdatingLocation = false
    private var isMonitoringSignificantChanges = false

    // Throttle for Firebase uploads
    private var lastUploadDate: Date?

    // MARK: - Init

    override init() {
        self.authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = GameConstants.significantLocationChangeDistance
    }

    // MARK: - Authorization

    /// Request "When In Use" permission. Call this early (e.g., on app launch or home screen).
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Escalate to "Always" permission. Only call when a game is starting and
    /// background location is needed for geofencing / tripwires.
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    var hasLocationPermission: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    var hasAlwaysPermission: Bool {
        authorizationStatus == .authorizedAlways
    }

    // MARK: - Location Updates

    /// Start continuous location updates. Use sparingly — prefer `startMonitoringSignificantChanges`
    /// for long-running background tracking.
    func startUpdatingLocation() {
        guard !isUpdatingLocation else { return }
        isUpdatingLocation = true
        locationManager.startUpdatingLocation()
    }

    /// Stop continuous location updates.
    func stopUpdatingLocation() {
        guard isUpdatingLocation else { return }
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }

    /// Start battery-efficient significant location change monitoring.
    /// Delivers updates roughly every 500m or when cell tower changes.
    func startMonitoringSignificantChanges() {
        guard !isMonitoringSignificantChanges else { return }
        isMonitoringSignificantChanges = true
        locationManager.startMonitoringSignificantLocationChanges()
    }

    /// Stop significant location change monitoring.
    func stopMonitoringSignificantChanges() {
        guard isMonitoringSignificantChanges else { return }
        isMonitoringSignificantChanges = false
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    /// Enable background location updates. Requires "Always" authorization
    /// and the `location` UIBackgroundMode in Info.plist.
    func enableBackgroundUpdates() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    /// Disable background location updates when no active game.
    func disableBackgroundUpdates() {
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = false
    }

    // MARK: - Geofencing

    /// Add a circular geofence for a tripwire. The system will notify
    /// via `lastTriggeredRegionId` when the user enters this region.
    func addGeofence(identifier: String, center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return
        }

        let clampedRadius = min(radius, locationManager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: center, radius: clampedRadius, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)
    }

    /// Remove a specific geofence by identifier.
    func removeGeofence(identifier: String) {
        for region in locationManager.monitoredRegions {
            if region.identifier == identifier {
                locationManager.stopMonitoring(for: region)
                break
            }
        }
    }

    /// Remove all monitored geofences.
    func removeAllGeofences() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    /// Returns the set of currently monitored region identifiers.
    var monitoredRegionIds: Set<String> {
        Set(locationManager.monitoredRegions.map(\.identifier))
    }

    // MARK: - Game Lifecycle

    /// Call when a game becomes active. Sets up appropriate monitoring.
    func startGameTracking() {
        if hasAlwaysPermission {
            enableBackgroundUpdates()
            startMonitoringSignificantChanges()
        } else {
            // Fall back to foreground-only updates
            startUpdatingLocation()
        }
    }

    /// Call when a game ends or the user leaves. Tears down monitoring.
    func stopGameTracking() {
        stopUpdatingLocation()
        stopMonitoringSignificantChanges()
        disableBackgroundUpdates()
        removeAllGeofences()
    }

    // MARK: - Upload Throttling

    /// Returns true if enough time has passed since the last upload
    /// (per `GameConstants.backgroundLocationUpdateInterval`).
    func shouldUploadLocation() -> Bool {
        guard let lastUpload = lastUploadDate else { return true }
        return Date().timeIntervalSince(lastUpload) >= GameConstants.backgroundLocationUpdateInterval
    }

    /// Mark that a location upload just occurred.
    func didUploadLocation() {
        lastUploadDate = Date()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.locationUpdateCount += 1
            self.locationError = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationError = error
        }
    }

    // MARK: Region Monitoring

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor in
            self.lastTriggeredRegionId = identifier
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let err = error
        Task { @MainActor in
            self.locationError = err
        }
    }
}

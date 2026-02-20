import Foundation
import CoreLocation

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
    private var userId: String?
    private var uploadTask: Task<Void, Never>?

    init(locationService: LocationService) {
        self.locationService = locationService
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

        do {
            try await locationRepository.uploadLocation(userId: userId, location: location)
            locationService.didUploadLocation()
            print("📍 [UserLocationManager] Location uploaded for userId=\(userId)")
        } catch {
            print("❌ [UserLocationManager] Upload failed: \(error)")
        }
    }
}

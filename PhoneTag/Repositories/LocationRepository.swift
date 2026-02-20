import Foundation
import CoreLocation
@preconcurrency import FirebaseDatabase

/// Handles reading and writing location data to Firebase Realtime Database.
/// Structure: /locations/{userId}/current { latitude, longitude, timestamp, accuracy }
actor LocationRepository {
    private let database = Database.database().reference()

    /// Upload the user's current location to Firebase.
    /// Also updates `lastUploadedAt` (used for 24-hour offline detection).
    func uploadLocation(userId: String, location: CLLocation) async throws {
        let locationData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "timestamp": ServerValue.timestamp(),
            "accuracy": location.horizontalAccuracy
        ]

        let userRef = database
            .child(GameConstants.FirebasePath.locations)
            .child(userId)

        try await userRef.child("current").setValue(locationData)
        try await userRef.child("lastUploadedAt").setValue(ServerValue.timestamp())
    }

    /// Fetches the server timestamp (ms since epoch) of the last location upload for a user.
    /// Returns nil if no upload has been recorded yet.
    func fetchLastUploadedAt(userId: String) async -> Double? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.locations)
                .child(userId)
                .child("lastUploadedAt")
                .getData()
            return snapshot.value as? Double
        } catch {
            return nil
        }
    }

    /// Fetch another user's most recent location. Returns nil if not available.
    func fetchLocation(for userId: String) async throws -> CLLocation? {
        let snapshot = try await database
            .child(GameConstants.FirebasePath.locations)
            .child(userId)
            .child("current")
            .getData()

        guard snapshot.exists(),
              let dict = snapshot.value as? [String: Any],
              let latitude = dict["latitude"] as? Double,
              let longitude = dict["longitude"] as? Double else {
            return nil
        }

        let accuracy = dict["accuracy"] as? Double ?? 0
        let timestamp: Date
        if let ts = dict["timestamp"] as? TimeInterval {
            timestamp = Date(timeIntervalSince1970: ts / 1000)
        } else {
            timestamp = Date()
        }

        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }
}

import Foundation
import UserNotifications
@preconcurrency import FirebaseMessaging
import FirebaseDatabase
import FirebaseFunctions

// MARK: - Notification Types

enum GameNotificationType: String {
    case gameInvite = "game_invite"
    case tagged = "tagged"
    case tripwireTriggered = "tripwire_triggered"
    case gameStarted = "game_started"
    case eliminated = "eliminated"
}

// MARK: - NotificationService

@MainActor
final class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var fcmToken: String?

    private let database = Database.database().reference()
    private let functions = Functions.functions()

    private override init() {
        super.init()
    }

    // MARK: - Permission Setup

    /// Call this once the user is authenticated (from AuthService or ContentView).
    /// Requests UNUserNotificationCenter permission and, on grant, registers for APNs.
    func setup() async {
        await refreshPermissionStatus()

        // If already granted, just register — don't re-prompt.
        if permissionStatus == .authorized || permissionStatus == .provisional {
            await registerWithAPNs()
            return
        }

        guard permissionStatus == .notDetermined else { return }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await registerWithAPNs()
            }
            await refreshPermissionStatus()
        } catch {
            print("❌ [NotificationService] Authorization request failed: \(error)")
        }
    }

    /// Refreshes the locally-cached permission status from the system.
    func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    // MARK: - APNs / FCM Registration

    /// Tells UIApplication to register for remote notifications. Must run on main thread.
    private func registerWithAPNs() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Called by AppDelegate when APNs vends a device token.
    /// Passes the token to FirebaseMessaging so it can derive the FCM token.
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Called by AppDelegate when APNs registration fails.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [NotificationService] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - FCM Token Management

    /// Fetches the current FCM token from Messaging and saves it to Firebase
    /// under `/fcmTokens/{userId}`. Call after a user successfully authenticates.
    func saveFCMToken(for userId: String) async {
        do {
            let token = try await Messaging.messaging().token()
            fcmToken = token
            try await database
                .child(GameConstants.FirebasePath.fcmTokens)
                .child(userId)
                .setValue(token)
            print("✅ [NotificationService] FCM token saved for userId=\(userId)")
        } catch {
            print("❌ [NotificationService] Failed to save FCM token: \(error)")
        }
    }

    /// Fetches the FCM token for a given user from Firebase.
    func fetchFCMToken(for userId: String) async -> String? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.fcmTokens)
                .child(userId)
                .getData()
            return snapshot.value as? String
        } catch {
            print("❌ [NotificationService] Failed to fetch FCM token for userId=\(userId): \(error)")
            return nil
        }
    }

    // MARK: - Send Game Invite Notification

    /// Sends a push notification to each invited player (those who are existing users).
    /// Uses a Firebase Cloud Function `sendGameInvite` to perform the actual FCM send
    /// (keeping server credentials off the device).
    ///
    /// - Parameters:
    ///   - gameId: The newly-created game's ID.
    ///   - gameTitle: Human-readable game title for the notification body.
    ///   - invitedByName: Display name of the player who created the game.
    ///   - playerIds: All player UIDs in the game (creator + invitees).
    ///   - creatorId: The UID of the game creator — they are excluded from receiving the invite.
    func sendGameInviteNotifications(
        gameId: String,
        gameTitle: String,
        invitedByName: String,
        playerIds: [String],
        creatorId: String
    ) async {
        let recipients = playerIds.filter { $0 != creatorId }
        guard !recipients.isEmpty else { return }

        // Collect FCM tokens for existing users
        var tokensForRecipients: [String: String] = [:]
        for userId in recipients {
            if let token = await fetchFCMToken(for: userId) {
                tokensForRecipients[userId] = token
            }
        }

        guard !tokensForRecipients.isEmpty else {
            print("ℹ️ [NotificationService] No FCM tokens found for recipients — skipping invite notifications.")
            return
        }

        // Call the Cloud Function with the token map + game details
        let payload: [String: Any] = [
            "gameId": gameId,
            "gameTitle": gameTitle,
            "invitedByName": invitedByName,
            "recipientTokens": tokensForRecipients
        ]

        do {
            _ = try await functions.httpsCallable("sendGameInvite").call(payload)
            print("✅ [NotificationService] Game invite notifications dispatched for gameId=\(gameId)")
        } catch {
            print("❌ [NotificationService] sendGameInvite Cloud Function error: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Show notifications as banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Handle taps on notifications.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let typeRaw = userInfo["type"] as? String,
              let type = GameNotificationType(rawValue: typeRaw) else { return }

        switch type {
        case .gameInvite:
            // Post so the UI can navigate to the game or show the invite
            if let gameId = userInfo["gameId"] as? String {
                NotificationCenter.default.post(
                    name: .didReceiveGameInvite,
                    object: nil,
                    userInfo: ["gameId": gameId]
                )
            }
        case .tagged:
            NotificationCenter.default.post(name: .didReceiveTaggedNotification, object: nil, userInfo: userInfo as? [String: Any])
        case .tripwireTriggered:
            NotificationCenter.default.post(name: .didReceiveTripwireNotification, object: nil, userInfo: userInfo as? [String: Any])
        case .gameStarted:
            if let gameId = userInfo["gameId"] as? String {
                NotificationCenter.default.post(
                    name: .didReceiveGameStarted,
                    object: nil,
                    userInfo: ["gameId": gameId]
                )
            }
        case .eliminated:
            NotificationCenter.default.post(name: .didReceiveEliminatedNotification, object: nil, userInfo: userInfo as? [String: Any])
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {

    /// Called whenever FCM vends a new or refreshed token.
    /// Re-saves it to Firebase so the stored token stays current.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        self.fcmToken = token
        print("ℹ️ [NotificationService] FCM token refreshed: \(token)")
        // The caller (AppDelegate / AuthService) should call saveFCMToken(for:) with the current userId
        NotificationCenter.default.post(
            name: .fcmTokenDidRefresh,
            object: nil,
            userInfo: ["fcmToken": token]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveGameInvite = Notification.Name("didReceiveGameInvite")
    static let didReceiveTaggedNotification = Notification.Name("didReceiveTaggedNotification")
    static let didReceiveTripwireNotification = Notification.Name("didReceiveTripwireNotification")
    static let didReceiveGameStarted = Notification.Name("didReceiveGameStarted")
    static let didReceiveEliminatedNotification = Notification.Name("didReceiveEliminatedNotification")
    static let fcmTokenDidRefresh = Notification.Name("fcmTokenDidRefresh")
}

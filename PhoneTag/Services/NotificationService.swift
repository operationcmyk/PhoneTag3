import Foundation
import UIKit
import UserNotifications
@preconcurrency import FirebaseMessaging
@preconcurrency import FirebaseDatabase
import FirebaseFunctions

// MARK: - Notification Types

enum GameNotificationType: String {
    case gameInvite = "game_invite"
    case tagged = "tagged"
    case tripwireTriggered = "tripwire_triggered"
    case gameStarted = "game_started"
    case eliminated = "eliminated"
    case playerReturned = "player_returned"
}

// MARK: - NotificationService

@MainActor
final class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var fcmToken: String?

    /// Kept so APNs/FCM callbacks can re-save the token without needing the caller to pass userId again.
    private(set) var currentUserId: String?

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
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        if let userId = currentUserId {
            Task { await saveFCMToken(for: userId) }
        }
    }

    /// Called by AppDelegate when APNs registration fails.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [NotificationService] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - FCM Token Management

    /// Fetches the current FCM token from Messaging and saves it to Firebase
    /// under `/fcmTokens/{userId}`. Call after a user successfully authenticates.
    func saveFCMToken(for userId: String) async {
        currentUserId = userId
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
        let ref = database
            .child(GameConstants.FirebasePath.fcmTokens)
            .child(userId)
        do {
            let snapshot = try await ref.getData()
            return snapshot.value as? String
        } catch {
            print("❌ [NotificationService] Failed to fetch FCM token for userId=\(userId): \(error)")
            return nil
        }
    }

    // MARK: - Generic Dispatcher (private)

    /// Sends a notification to a single recipient via the `sendNotification` Cloud Function.
    private func send(
        to token: String,
        title: String,
        body: String,
        data: [String: String],
        logLabel: String
    ) async {
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "data": data,
            "token": token
        ]
        do {
            _ = try await functions.httpsCallable("sendNotification").call(payload)
            print("✅ [NotificationService] \(logLabel) sent")
        } catch {
            print("❌ [NotificationService] \(logLabel) error: \(error)")
        }
    }

    /// Sends a notification to multiple recipients via the `sendNotification` Cloud Function.
    private func send(
        to tokens: [String: String],
        title: String,
        body: String,
        data: [String: String],
        logLabel: String
    ) async {
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "data": data,
            "tokens": tokens
        ]
        do {
            _ = try await functions.httpsCallable("sendNotification").call(payload)
            print("✅ [NotificationService] \(logLabel) dispatched to \(tokens.count) recipient(s)")
        } catch {
            print("❌ [NotificationService] \(logLabel) error: \(error)")
        }
    }

    /// Collects FCM tokens for a list of user IDs, excluding one (e.g. the sender).
    private func collectTokens(for userIds: [String], excluding excludedId: String? = nil) async -> [String: String] {
        var result: [String: String] = [:]
        for userId in userIds where userId != excludedId {
            if let token = await fetchFCMToken(for: userId) {
                result[userId] = token
            }
        }
        return result
    }

    // MARK: - Game Invite

    func sendGameInviteNotifications(
        gameId: String,
        gameTitle: String,
        invitedByName: String,
        playerIds: [String],
        creatorId: String
    ) async {
        let tokens = await collectTokens(for: playerIds, excluding: creatorId)
        guard !tokens.isEmpty else { return }
        await send(
            to: tokens,
            title: "Phone Tag — You've been invited!",
            body: "\(invitedByName) invited you to play \"\(gameTitle)\". Tap to join!",
            data: ["type": GameNotificationType.gameInvite.rawValue, "gameId": gameId, "gameTitle": gameTitle],
            logLabel: "Game invite (\(gameId))"
        )
    }

    // MARK: - Nudge

    func sendNudgeNotifications(
        gameId: String,
        gameTitle: String,
        nudgedByName: String,
        playerIds: [String],
        nudgerId: String
    ) async {
        let tokens = await collectTokens(for: playerIds, excluding: nudgerId)
        guard !tokens.isEmpty else { return }
        await send(
            to: tokens,
            title: "Phone Tag — Your turn!",
            body: "\(nudgedByName) is waiting for you in \"\(gameTitle)\". Get out there!",
            data: ["type": "nudge", "gameId": gameId, "gameTitle": gameTitle],
            logLabel: "Nudge (\(gameId))"
        )
    }

    // MARK: - Tag Warning

    func sendTagWarningNotification(
        to userId: String,
        taggerName: String,
        gameTitle: String
    ) async {
        guard let token = await fetchFCMToken(for: userId) else { return }
        await send(
            to: token,
            title: "📍 Tag incoming!",
            body: "Someone just dropped a tag near you in \"\(gameTitle)\" — you better get moving!",
            data: ["type": "tag_warning", "gameTitle": gameTitle, "taggerName": taggerName],
            logLabel: "Tag warning → \(userId)"
        )
    }

    // MARK: - Hit

    func sendHitNotification(
        to userId: String,
        taggerName: String,
        tagType: TagType,
        gameId: String,
        gameTitle: String
    ) async {
        guard let token = await fetchFCMToken(for: userId) else { return }
        let weaponLabel = tagType == .wideRadius ? "wide-radius tag" : "basic tag"
        await send(
            to: token,
            title: "💥 You've been tagged!",
            body: "\(taggerName) hit you with a \(weaponLabel) in \"\(gameTitle)\"! -1 life, loser.",
            data: ["type": GameNotificationType.tagged.rawValue, "gameId": gameId, "gameTitle": gameTitle, "taggerName": taggerName, "tagType": tagType.rawValue],
            logLabel: "Hit → \(userId)"
        )
    }

    // MARK: - Elimination

    func sendEliminationNotification(
        gameId: String,
        gameTitle: String,
        eliminatedPlayerName: String,
        playerIds: [String],
        eliminatedId: String
    ) async {
        let tokens = await collectTokens(for: playerIds, excluding: eliminatedId)
        guard !tokens.isEmpty else { return }
        await send(
            to: tokens,
            title: "☠️ Player eliminated!",
            body: "\(eliminatedPlayerName) has been eliminated from \"\(gameTitle)\"!  So Sad.",
            data: ["type": GameNotificationType.eliminated.rawValue, "gameId": gameId, "gameTitle": gameTitle, "eliminatedPlayerName": eliminatedPlayerName],
            logLabel: "Elimination (\(gameId))"
        )
    }

    // MARK: - Game Started

    func sendGameStartedNotification(
        gameId: String,
        gameTitle: String,
        playerIds: [String]
    ) async {
        let tokens = await collectTokens(for: playerIds)
        guard !tokens.isEmpty else { return }
        await send(
            to: tokens,
            title: "🏁 Game on!",
            body: "Everyone is set — \"\(gameTitle)\" has begun! LFG!",
            data: ["type": GameNotificationType.gameStarted.rawValue, "gameId": gameId, "gameTitle": gameTitle],
            logLabel: "Game started (\(gameId))"
        )
    }

    // MARK: - Player Returned

    func sendPlayerReturnedNotification(
        gameId: String,
        gameTitle: String,
        returnedPlayerName: String,
        playerIds: [String],
        returnedId: String
    ) async {
        let tokens = await collectTokens(for: playerIds, excluding: returnedId)
        guard !tokens.isEmpty else { return }
        await send(
            to: tokens,
            title: "👀 \(returnedPlayerName) is back!",
            body: "\(returnedPlayerName) just came back online in \"\(gameTitle)\" — no more hiding!",
            data: ["type": GameNotificationType.playerReturned.rawValue, "gameId": gameId, "gameTitle": gameTitle, "returnedPlayerName": returnedPlayerName],
            logLabel: "Player returned (\(gameId))"
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: @preconcurrency UNUserNotificationCenterDelegate {

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
        case .playerReturned:
            if let gameId = userInfo["gameId"] as? String {
                NotificationCenter.default.post(
                    name: .didReceivePlayerReturnedNotification,
                    object: nil,
                    userInfo: ["gameId": gameId]
                )
            }
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {

    /// Called whenever FCM vends a new or refreshed token.
    /// Re-saves it to Firebase so the stored token stays current.
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("ℹ️ [NotificationService] FCM token refreshed: \(token)")
        Task { @MainActor in
            self.fcmToken = token
            if let userId = self.currentUserId {
                await self.saveFCMToken(for: userId)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveGameInvite = Notification.Name("didReceiveGameInvite")
    static let didReceiveTaggedNotification = Notification.Name("didReceiveTaggedNotification")
    static let didReceiveTripwireNotification = Notification.Name("didReceiveTripwireNotification")
    static let didReceiveGameStarted = Notification.Name("didReceiveGameStarted")
    static let didReceiveEliminatedNotification = Notification.Name("didReceiveEliminatedNotification")
    static let didReceivePlayerReturnedNotification = Notification.Name("didReceivePlayerReturnedNotification")
}

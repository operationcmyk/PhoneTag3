import SwiftUI
import FirebaseCore
import FirebaseAuth
@preconcurrency import FirebaseMessaging
import UserNotifications

@main
struct PhoneTagApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // Set FCM delegate so we receive token refresh callbacks
        Messaging.messaging().delegate = NotificationService.shared

        // Set notification center delegate so we can show banners while the app is open
        UNUserNotificationCenter.current().delegate = NotificationService.shared

        // Register for APNs (required for both Phone Auth and push notifications)
        application.registerForRemoteNotifications()

        return true
    }

    // MARK: - APNs callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Forward to Firebase Auth (required for Phone Auth OTP)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)

        // Forward to NotificationService → Messaging so FCM can derive its token
        Task { @MainActor in
            NotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Let Firebase Auth handle its own silent push (e.g. Phone Auth verification)
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }
}

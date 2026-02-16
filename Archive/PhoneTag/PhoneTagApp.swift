import SwiftUI
import FirebaseCore

@main
struct PhoneTagApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

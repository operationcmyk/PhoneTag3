import SwiftUI

struct ContentView: View {
    @State private var authService = AuthService()
    @State private var gameRepository = FirebaseGameRepository()
    @State private var userRepository = FirebaseUserRepository()
    @State private var locationService = LocationService()
    @State private var contactsService = ContactsService()

    var body: some View {
        Group {
            switch authService.authState {
            case .unknown:
                ProgressView("Loading...")

            case .unauthenticated:
                LoginView(authService: authService)

            case .needsDisplayName:
                SetDisplayNameView(authService: authService)

            case .authenticated(let user):
                HomeView(
                    user: user,
                    authService: authService,
                    viewModel: HomeViewModel(userId: user.id, gameRepository: gameRepository),
                    userRepository: userRepository,
                    gameRepository: gameRepository,
                    locationService: locationService,
                    contactsService: contactsService
                )
                .task {
                    locationService.requestWhenInUseAuthorization()
                }
            }
        }
        .animation(.default, value: authService.authState.isAuthenticated)
    }
}

// Helper to make auth state changes animatable
extension AuthState {
    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    // Used so the transition from needsDisplayName → authenticated animates correctly
    var showsHomeContent: Bool { isAuthenticated }
}

#Preview {
    ContentView()
}

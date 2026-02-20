import SwiftUI

struct ContentView: View {
    @State private var authService = AuthService()
    @State private var gameRepository = FirebaseGameRepository()
    @State private var userRepository = FirebaseUserRepository()
    @State private var locationService = LocationService()
    @State private var contactsService = ContactsService()
    @State private var userLocationManager: UserLocationManager?
    @State private var homeViewModel: HomeViewModel?

    var body: some View {
        Group {
            switch authService.authState {
            case .unknown:
                ProgressView("Loading...")

            case .unauthenticated:
                LoginView(authService: authService)
                    .onAppear {
                        userLocationManager?.stop()
                        userLocationManager = nil
                        homeViewModel = nil
                    }

            case .needsDisplayName:
                SetDisplayNameView(authService: authService)

            case .authenticated(let user):
                let vm = homeViewModel ?? {
                    let newVM = HomeViewModel(userId: user.id, gameRepository: gameRepository)
                    return newVM
                }()
                HomeView(
                    user: user,
                    authService: authService,
                    viewModel: vm,
                    userRepository: userRepository,
                    gameRepository: gameRepository,
                    locationService: locationService,
                    contactsService: contactsService
                )
                .onAppear {
                    if homeViewModel == nil {
                        homeViewModel = vm
                    }
                }
                .onAppear {
                    // Start once per session; guard prevents restarting on every re-appear.
                    guard userLocationManager == nil else { return }
                    let manager = UserLocationManager(locationService: locationService, gameRepository: gameRepository)
                    manager.start(userId: user.id)
                    userLocationManager = manager
                }
                .onChange(of: locationService.locationUpdateCount) {
                    userLocationManager?.onLocationUpdate()
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

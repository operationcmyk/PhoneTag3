import SwiftUI

struct ContentView: View {
    @State private var authService = AuthService()
    @State private var gameRepository = MockGameRepository()
    @State private var userRepository = MockUserRepository()
    @State private var locationService = LocationService()

    var body: some View {
        let user = AuthService.mockUser
        HomeView(
            user: user,
            authService: authService,
            viewModel: HomeViewModel(userId: user.id, gameRepository: gameRepository),
            userRepository: userRepository,
            gameRepository: gameRepository,
            locationService: locationService
        )
        .task {
            locationService.requestWhenInUseAuthorization()
        }
    }
}

#Preview {
    ContentView()
}

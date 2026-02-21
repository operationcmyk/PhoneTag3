import SwiftUI

struct HomeView: View {
    let user: User
    let authService: AuthService
    @Bindable var viewModel: HomeViewModel
    let userRepository: any UserRepositoryProtocol
    let gameRepository: any GameRepositoryProtocol
    let locationService: LocationService
    let contactsService: ContactsService

    @State private var showingCreateGame = false
    @State private var showingJoinGame = false
    @State private var showingStore = false
    @State private var showingAddFriend = false
    @State private var showingProfile = false
    @State private var playerNames: [String: String] = [:]
    @State private var nudgingGameId: String? = nil
    @State private var nudgeConfirmationGame: Game? = nil

    var body: some View {
        NavigationStack {
            gameList
            .navigationTitle("Phone Tag")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingProfile = true
                        } label: {
                            Label("My Account", systemImage: "person.circle")
                        }
                        Button {
                            showingStore = true
                        } label: {
                            Label("Arsenal", systemImage: "flame.fill")
                        }
                        Divider()
                        Button(role: .destructive) {
                            authService.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Label("Menu", systemImage: "line.3.horizontal")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingAddFriend = true
                    } label: {
                        Label("Add Friend", systemImage: "person.badge.plus")
                    }
                    Button {
                        showingJoinGame = true
                    } label: {
                        Label("Join Game", systemImage: "person.badge.key.fill")
                    }
                    Button {
                        showingCreateGame = true
                    } label: {
                        Label("Start Game", systemImage: "plus.circle.fill")
                    }
                }
            }
            .refreshable {
                await viewModel.loadGames()
                await loadPlayerNames()
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView(user: user, authService: authService)
            }
            .sheet(isPresented: $showingJoinGame) {
                JoinGameView(
                    userId: user.id,
                    gameRepository: gameRepository
                ) { _ in
                    Task { await viewModel.loadGames() }
                }
            }
            .sheet(isPresented: $showingCreateGame) {
                CreateGameView(
                    userId: user.id,
                    userRepository: userRepository,
                    gameRepository: gameRepository,
                    contactsService: contactsService
                ) {
                    Task { await viewModel.loadGames() }
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendView(
                    currentUserId: user.id,
                    userRepository: userRepository
                )
            }
            .sheet(isPresented: $showingStore) {
                StoreView(
                    gameRepository: gameRepository,
                    userId: user.id,
                    games: viewModel.games
                ) {
                    Task { await viewModel.loadGames() }
                }
            }
            .navigationDestination(for: Game.ID.self) { gameId in
                if let game = viewModel.games.first(where: { $0.id == gameId }) {
                    GameBoardView(
                        viewModel: GameBoardViewModel(
                            game: game,
                            userId: user.id,
                            gameRepository: gameRepository,
                            userRepository: userRepository,
                            locationService: locationService
                        )
                    )
                }
            }
            .task {
                await viewModel.loadGames()
                await loadPlayerNames()
            }
            .confirmationDialog(
                nudgeConfirmationGame.map { "Nudge players in \"\($0.title)\"?" } ?? "",
                isPresented: Binding(
                    get: { nudgeConfirmationGame != nil },
                    set: { if !$0 { nudgeConfirmationGame = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let game = nudgeConfirmationGame {
                    Button("Nudge Everyone") {
                        nudgeConfirmationGame = nil
                        Task { await sendNudge(for: game) }
                    }
                    Button("Cancel", role: .cancel) {
                        nudgeConfirmationGame = nil
                    }
                }
            } message: {
                Text("This will send a push notification to all other players to remind them to play.")
            }
        }
    }

    private var gameList: some View {
        List {
            if viewModel.games.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Games Yet",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Pull to refresh, or tap \"Start Game\" to begin playing.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if !viewModel.activeGames.isEmpty {
                Section("Current Games") {
                    ForEach(viewModel.activeGames) { game in
                        NavigationLink(value: game.id) {
                            GameListRowView(
                                game: game,
                                currentUserId: user.id,
                                playerNames: playerNames
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                nudgeConfirmationGame = game
                            } label: {
                                Label("Nudge", systemImage: "bell.fill")
                            }
                            .tint(.orange)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                let game = viewModel.activeGames[index]
                                await viewModel.deleteGame(game)
                            }
                        }
                    }
                }
            }

            if !viewModel.completedGames.isEmpty {
                Section("Completed Games") {
                    ForEach(viewModel.completedGames) { game in
                        NavigationLink(value: game.id) {
                            GameListRowView(
                                game: game,
                                currentUserId: user.id,
                                playerNames: playerNames
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                let game = viewModel.completedGames[index]
                                await viewModel.deleteGame(game)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sendNudge(for game: Game) async {
        await NotificationService.shared.sendNudgeNotifications(
            gameId: game.id,
            gameTitle: game.title,
            nudgedByName: user.displayName,
            playerIds: Array(game.players.keys),
            nudgerId: user.id
        )
    }

    private func loadPlayerNames() async {
        var names: [String: String] = [:]
        let allPlayerIds = Set(viewModel.games.flatMap { $0.players.keys })
        for id in allPlayerIds {
            if let user = await userRepository.fetchUser(id) {
                names[id] = user.displayName
            }
        }
        playerNames = names
    }
}

import Foundation

@MainActor
@Observable
final class CreateGameViewModel {
    let userId: String
    let userRepository: any UserRepositoryProtocol
    let gameRepository: any GameRepositoryProtocol

    var friends: [User] = []
    var selectedPlayerIds: Set<String> = []
    var gameTitle = ""
    var isLoading = false
    var createdGame: Game?

    var canCreate: Bool {
        !selectedPlayerIds.isEmpty && !gameTitle.isEmpty
    }

    var trimmedTitle: String {
        String(gameTitle.prefix(GameConstants.gameTitleMaxLength)).uppercased()
    }

    init(userId: String, userRepository: any UserRepositoryProtocol, gameRepository: any GameRepositoryProtocol) {
        self.userId = userId
        self.userRepository = userRepository
        self.gameRepository = gameRepository
    }

    func loadFriends() async {
        friends = await userRepository.fetchFriends(for: userId)
    }

    func togglePlayer(_ id: String) {
        if selectedPlayerIds.contains(id) {
            selectedPlayerIds.remove(id)
        } else if selectedPlayerIds.count < GameConstants.maxAddablePlayers {
            selectedPlayerIds.insert(id)
        }
    }

    func submitGame() async {
        guard canCreate else { return }
        isLoading = true
        let game = await gameRepository.createGame(
            createdBy: userId,
            title: trimmedTitle,
            playerIds: Array(selectedPlayerIds)
        )
        createdGame = game
        isLoading = false
    }
}

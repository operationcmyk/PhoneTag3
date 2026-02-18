import Foundation

@MainActor
@Observable
final class HomeViewModel {
    let userId: String
    let gameRepository: any GameRepositoryProtocol

    var games: [Game] = []
    var isLoading = false

    var activeGames: [Game] {
        games.filter { $0.status == .active || $0.status == .waiting }
    }

    var completedGames: [Game] {
        games.filter { $0.status == .completed }
    }

    init(userId: String, gameRepository: any GameRepositoryProtocol) {
        self.userId = userId
        self.gameRepository = gameRepository
    }

    func loadGames() async {
        isLoading = true
        games = await gameRepository.fetchGames(for: userId)
        isLoading = false
    }

    func deleteGame(_ game: Game) async {
        await gameRepository.deleteGame(id: game.id)
        games.removeAll { $0.id == game.id }
    }
}

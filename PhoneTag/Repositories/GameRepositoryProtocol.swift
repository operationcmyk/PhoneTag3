import Foundation
import CoreLocation

@MainActor
protocol GameRepositoryProtocol {
    func fetchGames(for userId: String) async -> [Game]
    func fetchGame(by id: String) async -> Game?
    func createGame(createdBy: String, title: String, playerIds: [String]) async -> Game
    func updatePlayerState(gameId: String, userId: String, state: PlayerState) async
    func deleteGame(id: String) async
    func submitTag(gameId: String, fromUserId: String, guessedLocation: CLLocationCoordinate2D, tagType: TagType) async -> TagResult
    func decrementItem(gameId: String, userId: String, item: ArsenalItem)
    func useRadar(gameId: String, userId: String)
    func placeTripwire(gameId: String, userId: String, tripwire: Tripwire)
    func purchaseItem(userId: String, product: StoreProduct) async
    func resetDailyTagsIfNeeded(gameId: String, userId: String)
}

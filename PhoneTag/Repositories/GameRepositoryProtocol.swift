import Foundation
import CoreLocation

@MainActor
protocol GameRepositoryProtocol {
    func fetchGames(for userId: String) async -> [Game]
    func fetchGame(by id: String) async -> Game?
    func createGame(createdBy: String, title: String, playerIds: [String]) async -> Game
    func updatePlayerState(gameId: String, userId: String, state: PlayerState) async
    func deleteGame(id: String) async
    func leaveGame(gameId: String, userId: String) async
    func submitTag(gameId: String, fromUserId: String, guessedLocation: CLLocationCoordinate2D, tagType: TagType) async -> TagResult
    func decrementItem(gameId: String, userId: String, item: ArsenalItem)
    func useRadar(gameId: String, userId: String)
    func placeTripwire(gameId: String, userId: String, tripwire: Tripwire)
    func purchaseItem(userId: String, product: StoreProduct) async
    func resetDailyTagsIfNeeded(gameId: String, userId: String)
    func joinGame(byCode code: String, userId: String) async -> Game?
    /// Deducts one strike from a player who has been offline for 48h.
    /// Returns the player's name and whether they were eliminated (strikes hit 0).
    func deductStrikeForInactivity(gameId: String, userId: String) async -> (playerName: String, wasEliminated: Bool)?

    /// Called when the current user crosses another player's tripwire.
    /// Deducts a strike from the triggered user, creates a permanent safe zone at the tripwire
    /// location, removes the tripwire, and sends appropriate notifications.
    /// Returns the TagResult so the UI can display the outcome.
    func processTripwireHit(tripwireId: String, gameId: String, triggeredByUserId: String) async -> TagResult?
}

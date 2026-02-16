import Foundation

@MainActor
protocol UserRepositoryProtocol {
    func fetchUser(_ id: String) async -> User?
    func fetchFriends(for userId: String) async -> [User]
    func searchUsers(query: String) async -> [User]
}

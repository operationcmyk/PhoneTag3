import Foundation

@MainActor
protocol UserRepositoryProtocol {
    func fetchUser(_ id: String) async -> User?
    func fetchFriends(for userId: String) async -> [User]
    func searchUsers(query: String) async -> [User]
    /// Looks up a user by phone number and adds them as a friend of `userId`.
    /// Returns an error message string on failure, or nil on success.
    func addFriend(userId: String, friendPhone: String) async -> String?
}

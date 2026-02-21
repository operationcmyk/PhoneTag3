import Foundation

@MainActor
@Observable
final class MockUserRepository: UserRepositoryProtocol {
    var users: [User]

    init() {
        users = [
            User(
                id: "mock-user-001",
                phoneNumber: "+15551234567",
                displayName: "Player 1",
                createdAt: Date(),
                friendIds: ["mock-user-002", "mock-user-003", "mock-user-004", "mock-user-005"],
                activeGameIds: []
            ),
            User(
                id: "mock-user-002",
                phoneNumber: "+15559876543",
                displayName: "Player 2",
                createdAt: Date(),
                friendIds: ["mock-user-001"],
                activeGameIds: []
            ),
            User(
                id: "mock-user-003",
                phoneNumber: "+15555551234",
                displayName: "Player 3",
                createdAt: Date(),
                friendIds: ["mock-user-001"],
                activeGameIds: []
            ),
            User(
                id: "mock-user-004",
                phoneNumber: "+15554443322",
                displayName: "Player 4",
                createdAt: Date(),
                friendIds: ["mock-user-001"],
                activeGameIds: []
            ),
            User(
                id: "mock-user-005",
                phoneNumber: "+15556667788",
                displayName: "Player 5",
                createdAt: Date(),
                friendIds: ["mock-user-001"],
                activeGameIds: []
            ),
        ]
    }

    func fetchUser(_ id: String) async -> User? {
        users.first { $0.id == id }
    }

    func fetchFriends(for userId: String) async -> [User] {
        guard let user = users.first(where: { $0.id == userId }) else {
            // Real Firebase UID — not in mock data. Return all mock users as friends.
            return users
        }
        return users.filter { user.friendIds.contains($0.id) }
    }

    func searchUsers(query: String) async -> [User] {
        let lowered = query.lowercased()
        return users.filter {
            $0.displayName.lowercased().contains(lowered) ||
            ($0.phoneNumber?.contains(lowered) ?? false)
        }
    }

    func updateDisplayName(userId: String, displayName: String) async throws {
        guard let idx = users.firstIndex(where: { $0.id == userId }) else { return }
        users[idx] = User(
            id: users[idx].id,
            phoneNumber: users[idx].phoneNumber,
            displayName: displayName,
            createdAt: users[idx].createdAt,
            friendIds: users[idx].friendIds,
            activeGameIds: users[idx].activeGameIds
        )
    }

    func fetchUsersByPhones(_ phones: [String]) async -> [User] {
        users.filter { user in
            guard let phone = user.phoneNumber else { return false }
            return phones.contains(phone)
        }
    }

    func addFriend(userId: String, friendPhone: String) async -> String? {
        guard let friend = users.first(where: { $0.phoneNumber == friendPhone }) else {
            return "No user found with that phone number."
        }
        guard friend.id != userId else { return "You can't add yourself." }
        guard let idx = users.firstIndex(where: { $0.id == userId }) else { return "User not found." }
        if users[idx].friendIds.contains(friend.id) {
            return "You're already friends with \(friend.displayName)."
        }
        users[idx].friendIds.append(friend.id)
        return nil
    }
}

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
        guard let user = users.first(where: { $0.id == userId }) else { return [] }
        return users.filter { user.friendIds.contains($0.id) }
    }

    func searchUsers(query: String) async -> [User] {
        let lowered = query.lowercased()
        return users.filter {
            $0.displayName.lowercased().contains(lowered) ||
            $0.phoneNumber.contains(lowered)
        }
    }
}

import Foundation
@preconcurrency import FirebaseDatabase

@MainActor
final class FirebaseUserRepository: UserRepositoryProtocol {
    private let database = Database.database().reference()

    // MARK: - UserRepositoryProtocol

    func fetchUser(_ id: String) async -> User? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.users)
                .child(id)
                .getData()
            guard snapshot.exists(), let dict = snapshot.value as? [String: Any] else { return nil }
            return parseUser(id: id, dict: dict)
        } catch {
            return nil
        }
    }

    func fetchFriends(for userId: String) async -> [User] {
        guard let user = await fetchUser(userId) else { return [] }
        var friends: [User] = []
        for friendId in user.friendIds {
            if let friend = await fetchUser(friendId) {
                friends.append(friend)
            }
        }
        return friends
    }

    func searchUsers(query: String) async -> [User] {
        if let user = await searchByPhone(query) { return [user] }
        return []
    }

    func addFriend(userId: String, friendPhone: String) async -> String? {
        guard let friend = await searchByPhone(friendPhone) else {
            return "No user found with that phone number."
        }
        guard friend.id != userId else {
            return "You can't add yourself."
        }
        guard let currentUser = await fetchUser(userId) else {
            return "Could not load your profile."
        }
        if currentUser.friendIds.contains(friend.id) {
            return "You're already friends with \(friend.displayName)."
        }
        do {
            try await appendFriendId(friend.id, toUser: userId)
            try await appendFriendId(userId, toUser: friend.id)
            return nil
        } catch {
            return "Failed to add friend: \(error.localizedDescription)"
        }
    }

    // MARK: - User Creation (used by AuthService)

    func createUser(uid: String, phoneNumber: String, displayName: String) async throws -> User {
        let userRef = database.child(GameConstants.FirebasePath.users).child(uid)
        let userData: [String: Any] = [
            "id": uid,
            "phoneNumber": phoneNumber,
            "displayName": displayName,
            "createdAt": ServerValue.timestamp(),
            "friendIds": [String](),
            "activeGameIds": [String]()
        ]
        try await userRef.setValue(userData)
        return User(
            id: uid,
            phoneNumber: phoneNumber,
            displayName: displayName,
            createdAt: Date(),
            friendIds: [],
            activeGameIds: []
        )
    }

    // MARK: - Private

    private func searchByPhone(_ phone: String) async -> User? {
        do {
            let snapshot = try await database
                .child(GameConstants.FirebasePath.users)
                .queryOrdered(byChild: "phoneNumber")
                .queryEqual(toValue: phone)
                .getData()
            guard snapshot.exists(),
                  let dict = snapshot.value as? [String: Any],
                  let firstKey = dict.keys.first,
                  let userDict = dict[firstKey] as? [String: Any] else { return nil }
            return parseUser(id: firstKey, dict: userDict)
        } catch {
            return nil
        }
    }

    private func appendFriendId(_ friendId: String, toUser userId: String) async throws {
        let ref = database
            .child(GameConstants.FirebasePath.users)
            .child(userId)
            .child("friendIds")
        let snapshot = try await ref.getData()
        var ids = (snapshot.value as? [String]) ?? []
        guard !ids.contains(friendId) else { return }
        ids.append(friendId)
        try await ref.setValue(ids)
    }

    private func parseUser(id: String, dict: [String: Any]) -> User {
        let phoneNumber = dict["phoneNumber"] as? String ?? ""
        let displayName = dict["displayName"] as? String ?? "Player"
        let friendIds = dict["friendIds"] as? [String] ?? []
        let activeGameIds = dict["activeGameIds"] as? [String] ?? []
        let createdAt: Date
        if let ts = dict["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: ts / 1000)
        } else {
            createdAt = Date()
        }
        return User(
            id: id,
            phoneNumber: phoneNumber,
            displayName: displayName,
            createdAt: createdAt,
            friendIds: friendIds,
            activeGameIds: activeGameIds
        )
    }
}

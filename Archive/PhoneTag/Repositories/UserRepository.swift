import Foundation
@preconcurrency import FirebaseDatabase

actor UserRepository {
    private let database = Database.database().reference()

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

    func fetchUser(_ uid: String) async throws -> User? {
        let snapshot = try await database
            .child(GameConstants.FirebasePath.users)
            .child(uid)
            .getData()

        guard snapshot.exists(),
              let dict = snapshot.value as? [String: Any] else {
            return nil
        }

        let id = dict["id"] as? String ?? uid
        let phoneNumber = dict["phoneNumber"] as? String ?? ""
        let displayName = dict["displayName"] as? String ?? ""
        let friendIds = dict["friendIds"] as? [String] ?? []
        let activeGameIds = dict["activeGameIds"] as? [String] ?? []

        let createdAt: Date
        if let timestamp = dict["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: timestamp / 1000)
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

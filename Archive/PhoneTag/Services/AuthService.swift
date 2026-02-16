import Foundation

enum AuthState: Sendable {
    case unknown
    case unauthenticated
    case authenticated(User)
}

@MainActor
@Observable
final class AuthService {
    var authState: AuthState = .unknown

    static let mockUser = User(
        id: "mock-user-001",
        phoneNumber: "+15551234567",
        displayName: "Player 1",
        createdAt: Date(),
        friendIds: ["mock-user-002", "mock-user-003", "mock-user-004", "mock-user-005"],
        activeGameIds: []
    )

    init() {
        authState = .authenticated(Self.mockUser)
    }

    func signOut() {
        // No-op for mock auth
    }
}

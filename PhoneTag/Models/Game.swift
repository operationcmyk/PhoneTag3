import Foundation

struct Game: Identifiable, Codable, Sendable {
    let id: String
    var title: String
    var registrationCode: String
    let createdAt: Date
    var players: [String: PlayerState] // userId: PlayerState
    let createdBy: String
    var status: GameStatus
    var startedAt: Date?
    var endedAt: Date?
    /// When a nudge was issued. Used to determine which logins count as "after the nudge".
    var nudgeIssuedAt: Date?
    /// Deadline by which all players must log in or lose a life (nudgeIssuedAt + 6h).
    var nudgeDeadlineAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case registrationCode
        case createdAt
        case players
        case createdBy
        case status
        case startedAt
        case endedAt
        case nudgeIssuedAt
        case nudgeDeadlineAt
    }
}

enum GameStatus: String, Codable, Sendable {
    case waiting    // Waiting for all players to set home bases
    case active     // Game is running
    case completed  // Game has ended
}

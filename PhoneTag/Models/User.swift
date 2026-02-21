import Foundation

struct User: Identifiable, Codable, Sendable {
    let id: String // Firebase Auth UID
    let phoneNumber: String?  // nil for email-registered users
    let displayName: String
    let createdAt: Date
    var friendIds: [String]
    var activeGameIds: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber
        case displayName
        case createdAt
        case friendIds
        case activeGameIds
    }
}

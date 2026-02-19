import Foundation

@MainActor
@Observable
final class CreateGameViewModel {
    let userId: String
    let userRepository: any UserRepositoryProtocol
    let gameRepository: any GameRepositoryProtocol
    let contactsService: ContactsService

    // MARK: - Player lists

    /// Friends already in the app
    var appFriends: [User] = []

    /// Contacts who are on PhoneTag but not yet friends
    var appContacts: [User] = []

    /// Device contacts NOT on the app (phone number only — for share-code invites)
    var offAppContacts: [DeviceContact] = []

    // MARK: - Selection

    /// User IDs selected to be added directly to the game
    var selectedPlayerIds: Set<String> = []

    /// Device contacts selected to receive a share-code invite message
    var selectedInviteContacts: Set<String> = []  // DeviceContact.id

    // MARK: - Other state

    var gameTitle = ""
    var isLoading = false
    var contactsPermissionDenied = false
    var createdGame: Game?

    var canCreate: Bool { !gameTitle.isEmpty }

    var trimmedTitle: String {
        String(gameTitle.prefix(GameConstants.gameTitleMaxLength)).uppercased()
    }

    init(
        userId: String,
        userRepository: any UserRepositoryProtocol,
        gameRepository: any GameRepositoryProtocol,
        contactsService: ContactsService
    ) {
        self.userId = userId
        self.userRepository = userRepository
        self.gameRepository = gameRepository
        self.contactsService = contactsService
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Always load app friends first (no permission needed)
        appFriends = await userRepository.fetchFriends(for: userId)

        // Request contacts access and cross-reference
        let granted = await contactsService.requestAccess()
        if !granted {
            contactsPermissionDenied = true
            return
        }

        let deviceContacts = await contactsService.fetchContacts()
        let friendPhones = Set(appFriends.map { $0.phoneNumber })

        // All unique normalized phone numbers from device contacts
        let allContactPhones = Array(
            Set(deviceContacts.flatMap { $0.phoneNumbers })
        )

        // Look up which of those phones are registered PhoneTag users
        let onAppUsers = await userRepository.fetchUsersByPhones(allContactPhones)

        // Exclude self and existing friends
        let friendIds = Set(appFriends.map { $0.id })
        appContacts = onAppUsers.filter { $0.id != userId && !friendIds.contains($0.id) }

        // On-app phone numbers (for exclusion from off-app list)
        let onAppPhones = Set(onAppUsers.map { $0.phoneNumber }).union(friendPhones)

        // Off-app contacts: device contacts where NONE of their numbers are on the app
        offAppContacts = deviceContacts.filter { contact in
            !contact.phoneNumbers.contains(where: { onAppPhones.contains($0) })
        }
        .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Toggle selection

    func togglePlayer(_ id: String) {
        if selectedPlayerIds.contains(id) {
            selectedPlayerIds.remove(id)
        } else if selectedPlayerIds.count < GameConstants.maxAddablePlayers {
            selectedPlayerIds.insert(id)
        }
    }

    func toggleInviteContact(_ id: String) {
        if selectedInviteContacts.contains(id) {
            selectedInviteContacts.remove(id)
        } else {
            selectedInviteContacts.insert(id)
        }
    }

    // MARK: - Submit

    func submitGame() async {
        guard !gameTitle.isEmpty else { return }
        isLoading = true
        let game = await gameRepository.createGame(
            createdBy: userId,
            title: trimmedTitle,
            playerIds: Array(selectedPlayerIds)
        )
        createdGame = game
        isLoading = false
    }

    // MARK: - Share message

    func shareMessage(for game: Game) -> String {
        "Join my Phone Tag game \"\(game.title)\"! Use code: \(game.registrationCode)"
    }

    /// Phone numbers to pre-populate in the share sheet (selected off-app contacts)
    var selectedInvitePhones: [String] {
        offAppContacts
            .filter { selectedInviteContacts.contains($0.id) }
            .compactMap { $0.phoneNumbers.first }
    }
}

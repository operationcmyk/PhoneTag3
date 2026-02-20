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

    /// People you've played with (past or current games) who aren't already friends
    var recentPlayers: [User] = []

    /// Contacts who are on PhoneTag but not yet friends or recent players
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
    /// True while Phase 1 (friends + recent players) is loading — shows full-screen spinner
    var isLoading = false
    /// True while Phase 2 (device contacts cross-referenced with Firebase) is loading — shows inline spinners
    var isLoadingContacts = false
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

        // ── Phase 1: Instant ──
        // Friends (direct ID lookups — fast)
        appFriends = await userRepository.fetchFriends(for: userId)

        // Recent players: anyone you've been in a game with
        let friendIds = Set(appFriends.map(\.id))
        recentPlayers = await fetchRecentPlayers(excluding: friendIds)

        // Phase 1 done — render immediately
        isLoading = false

        // ── Phase 2: Background contacts ──
        isLoadingContacts = true
        defer { isLoadingContacts = false }

        let granted = await contactsService.requestAccess()
        if !granted {
            contactsPermissionDenied = true
            return
        }

        let deviceContacts = await contactsService.fetchContacts()
        let friendPhones = Set(appFriends.map(\.phoneNumber))

        // All unique normalized phone numbers from device contacts
        let allContactPhones = Array(
            Set(deviceContacts.flatMap(\.phoneNumbers))
        )

        // Look up which of those phones are registered PhoneTag users (now batched/concurrent)
        let onAppUsers = await userRepository.fetchUsersByPhones(allContactPhones)

        // Exclude self, existing friends, and recent players
        let knownIds = friendIds.union(Set(recentPlayers.map(\.id)))
        appContacts = onAppUsers.filter { $0.id != userId && !knownIds.contains($0.id) }

        // On-app phone numbers (for exclusion from off-app list)
        let recentPlayerPhones = Set(recentPlayers.map(\.phoneNumber))
        let onAppPhones = Set(onAppUsers.map(\.phoneNumber))
            .union(friendPhones)
            .union(recentPlayerPhones)

        // Off-app contacts: device contacts where NONE of their numbers are on the app
        offAppContacts = deviceContacts.filter { contact in
            !contact.phoneNumbers.contains(where: { onAppPhones.contains($0) })
        }
        .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Recent Players

    /// Collects every player ID from the user's games (past & present),
    /// fetches their User objects, and returns those who aren't the current user or existing friends.
    private func fetchRecentPlayers(excluding friendIds: Set<String>) async -> [User] {
        let games = await gameRepository.fetchGames(for: userId)
        let allPlayerIds = Set(games.flatMap { $0.players.keys })
            .subtracting([userId])
            .subtracting(friendIds)

        guard !allPlayerIds.isEmpty else { return [] }

        var users: [User] = []
        for playerId in allPlayerIds {
            if let user = await userRepository.fetchUser(playerId) {
                users.append(user)
            }
        }
        return users.sorted { $0.displayName < $1.displayName }
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

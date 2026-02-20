import Foundation
@preconcurrency import FirebaseAuth


enum AuthState: Sendable {
    case unknown
    case unauthenticated
    case needsDisplayName(uid: String, phoneNumber: String)  // first login, no profile yet
    case authenticated(User)
}

@MainActor
@Observable
final class AuthService {
    var authState: AuthState = .unknown

    // Phone auth flow state
    var verificationID: String?
    var isLoading = false
    var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private let userRepository = FirebaseUserRepository()

    init() {
        listenToAuthState()
    }

    // MARK: - Auth State Listener

    private func listenToAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let firebaseUser {
                    await self.loadUser(firebaseUser: firebaseUser)
                } else {
                    self.authState = .unauthenticated
                }
            }
        }
    }

    private func loadUser(firebaseUser: FirebaseAuth.User) async {
        if let user = await userRepository.fetchUser(firebaseUser.uid) {
            authState = .authenticated(user)
            await setupNotifications(for: user.id)
        } else {
            // First login — prompt the user to choose a display name
            authState = .needsDisplayName(
                uid: firebaseUser.uid,
                phoneNumber: firebaseUser.phoneNumber ?? ""
            )
        }
    }

    // MARK: - Notifications

    /// Requests push notification permission (if not yet determined) and saves the
    /// FCM token to Firebase so this user can receive game invites.
    private func setupNotifications(for userId: String) async {
        await NotificationService.shared.setup()
        await NotificationService.shared.saveFCMToken(for: userId)
    }

    /// Called from SetDisplayNameView once the user submits their chosen name.
    func createProfile(displayName: String) async {
        guard case .needsDisplayName(let uid, let phone) = authState else { return }
        isLoading = true
        do {
            let user = try await userRepository.createUser(uid: uid, phoneNumber: phone, displayName: displayName)
            authState = .authenticated(user)
            await setupNotifications(for: uid)
        } catch {
            // DB write failed — proceed with a local profile so the user isn't stuck
            let user = User(id: uid, phoneNumber: phone, displayName: displayName,
                            createdAt: Date(), friendIds: [], activeGameIds: [])
            authState = .authenticated(user)
            await setupNotifications(for: uid)
        }
        isLoading = false
    }

    // MARK: - Phone Auth

    func sendVerificationCode(to phoneNumber: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let id = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            verificationID = id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func verifyCode(_ code: String) async {
        guard let verificationID else {
            errorMessage = "No verification ID. Request a code first."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            try await Auth.auth().signIn(with: credential)
            // Auth state listener will fire and update authState
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Profile Updates

    /// Updates the display name in Firebase and refreshes the local auth state.
    func updateDisplayName(_ newName: String) async throws {
        guard let user = currentUser else { return }
        try await userRepository.updateDisplayName(userId: user.id, displayName: newName)
        // Refresh local state with the new name
        let updated = User(
            id: user.id,
            phoneNumber: user.phoneNumber,
            displayName: newName,
            createdAt: user.createdAt,
            friendIds: user.friendIds,
            activeGameIds: user.activeGameIds
        )
        authState = .authenticated(updated)
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            authState = .unauthenticated
            verificationID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Current User Helpers

    var currentUser: User? {
        if case .authenticated(let user) = authState {
            return user
        }
        return nil
    }

    var currentUserId: String? {
        currentUser?.id
    }
}

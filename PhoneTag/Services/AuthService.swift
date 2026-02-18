import Foundation
@preconcurrency import FirebaseAuth

enum AuthState: Sendable {
    case unknown
    case unauthenticated
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

    private let userRepository = UserRepository()

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
        do {
            if let user = try await userRepository.fetchUser(firebaseUser.uid) {
                authState = .authenticated(user)
            } else {
                // First login — create user record in database
                let displayName = firebaseUser.displayName ?? "Player"
                let phone = firebaseUser.phoneNumber ?? ""
                let user = try await userRepository.createUser(
                    uid: firebaseUser.uid,
                    phoneNumber: phone,
                    displayName: displayName
                )
                authState = .authenticated(user)
            }
        } catch {
            // Firebase is reachable (user is authenticated) but DB failed —
            // fall back to a minimal local User so the app isn't stuck.
            let user = User(
                id: firebaseUser.uid,
                phoneNumber: firebaseUser.phoneNumber ?? "",
                displayName: firebaseUser.displayName ?? "Player",
                createdAt: Date(),
                friendIds: [],
                activeGameIds: []
            )
            authState = .authenticated(user)
        }
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

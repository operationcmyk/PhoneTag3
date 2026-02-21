import SwiftUI

struct LoginView: View {
    @Bindable var authService: AuthService

    @State private var authMode: AuthMode = .phone
    @State private var phoneStep: PhoneStep = .entry
    @State private var emailStep: EmailStep = .signIn

    // Phone fields
    @State private var phoneNumber = "+1"
    @State private var verificationCode = ""

    // Email fields
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    enum AuthMode { case phone, email }
    enum PhoneStep { case entry, code }
    enum EmailStep { case signIn, register }

    // Accent color used for active buttons and borders
    private let accent = Color(red: 0.25, green: 0.65, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(accent)
                Text("PHONE TAG")
                    .font(.title.weight(.black))
                    .tracking(2)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 36)

            // Auth mode toggle (only show when not mid-flow)
            if phoneStep == .entry {
                Picker("Sign in method", selection: $authMode) {
                    Text("Phone").tag(AuthMode.phone)
                    Text("Email").tag(AuthMode.email)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .onChange(of: authMode) {
                    authService.errorMessage = nil
                    emailStep = .signIn
                    email = ""
                    password = ""
                    confirmPassword = ""
                }
            }

            // Form area
            VStack(spacing: 16) {
                switch authMode {
                case .phone:
                    switch phoneStep {
                    case .entry: phoneEntryStep
                    case .code:  phoneCodeStep
                    }
                case .email:
                    switch emailStep {
                    case .signIn:   emailSignInStep
                    case .register: emailRegisterStep
                    }
                }

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    // MARK: - Phone: Entry Step

    private var phoneEntryStep: some View {
        VStack(spacing: 16) {
            loginField(icon: "phone.fill", placeholder: "e.g. +1 555 000 0000", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)

            Text("Include your country code")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            primaryButton("Send Verification Code", disabled: phoneNumber.isEmpty) {
                Task {
                    await authService.sendVerificationCode(to: phoneNumber)
                    if authService.errorMessage == nil {
                        phoneStep = .code
                    }
                }
            }
        }
    }

    // MARK: - Phone: Verification Code Step

    private var phoneCodeStep: some View {
        VStack(spacing: 16) {
            loginField(icon: "lock.fill", placeholder: "6-digit code", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            Text("Enter the code sent to \(phoneNumber)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            primaryButton("Verify & Sign In", disabled: verificationCode.count < 6) {
                Task { await authService.verifyCode(verificationCode) }
            }

            Button {
                phoneStep = .entry
                verificationCode = ""
                authService.errorMessage = nil
            } label: {
                Text("Use a different number")
                    .font(.subheadline)
                    .foregroundStyle(accent.opacity(0.8))
            }
        }
    }

    // MARK: - Email: Sign In Step

    private var emailSignInStep: some View {
        VStack(spacing: 16) {
            loginField(icon: "envelope.fill", placeholder: "Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)

            secureLoginField(icon: "lock.fill", placeholder: "Password", text: $password)
                .textContentType(.password)

            primaryButton("Sign In", disabled: email.isEmpty || password.isEmpty) {
                Task { await authService.signInWithEmail(email: email, password: password) }
            }

            Button {
                authService.errorMessage = nil
                password = ""
                confirmPassword = ""
                emailStep = .register
            } label: {
                Text("Don't have an account? Create one")
                    .font(.subheadline)
                    .foregroundStyle(accent.opacity(0.8))
            }
        }
    }

    // MARK: - Email: Register Step

    private var emailRegisterStep: some View {
        VStack(spacing: 16) {
            loginField(icon: "envelope.fill", placeholder: "Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)

            secureLoginField(icon: "lock.fill", placeholder: "Password (min 6 characters)", text: $password)
                .textContentType(.newPassword)

            secureLoginField(icon: "lock.fill", placeholder: "Confirm password", text: $confirmPassword)
                .textContentType(.newPassword)

            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords don't match.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
            }

            primaryButton("Create Account",
                          disabled: email.isEmpty || password.count < 6 || password != confirmPassword) {
                Task { await authService.registerWithEmail(email: email, password: password) }
            }

            Button {
                authService.errorMessage = nil
                password = ""
                confirmPassword = ""
                emailStep = .signIn
            } label: {
                Text("Already have an account? Sign in")
                    .font(.subheadline)
                    .foregroundStyle(accent.opacity(0.8))
            }
        }
    }

    // MARK: - Field Helpers

    /// Standard text field with an icon and visible background
    @ViewBuilder
    private func loginField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            TextField(placeholder, text: text)
                .foregroundStyle(.white)
                .tint(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    /// Secure field variant (for passwords)
    @ViewBuilder
    private func secureLoginField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            SecureField(placeholder, text: text)
                .foregroundStyle(.white)
                .tint(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Primary Button

    @ViewBuilder
    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if authService.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(disabled ? Color.white.opacity(0.15) : accent)
            .foregroundStyle(disabled ? .white.opacity(0.4) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(disabled || authService.isLoading)
    }
}

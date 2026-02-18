import SwiftUI

struct LoginView: View {
    @Bindable var authService: AuthService

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var step: LoginStep = .phone

    enum LoginStep {
        case phone
        case code
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo area
            VStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                Text("PHONE TAG")
                    .font(.title.weight(.black))
                    .tracking(2)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 48)

            // Form
            VStack(spacing: 16) {
                switch step {
                case .phone:
                    phoneStep
                case .code:
                    codeStep
                }

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    // MARK: - Phone Number Step

    private var phoneStep: some View {
        VStack(spacing: 16) {
            TextField("Phone number", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding()
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)

            Text("Enter your phone number with country code (e.g. +1...)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            Button {
                Task {
                    await authService.sendVerificationCode(to: phoneNumber)
                    if authService.errorMessage == nil {
                        step = .code
                    }
                }
            } label: {
                Group {
                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send Code")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(phoneNumber.isEmpty ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(phoneNumber.isEmpty || authService.isLoading)
        }
    }

    // MARK: - Verification Code Step

    private var codeStep: some View {
        VStack(spacing: 16) {
            TextField("6-digit code", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)

            Text("Enter the verification code sent to \(phoneNumber)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await authService.verifyCode(verificationCode)
                }
            } label: {
                Group {
                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Verify")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(verificationCode.count < 6 ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(verificationCode.count < 6 || authService.isLoading)

            Button {
                step = .phone
                verificationCode = ""
                authService.errorMessage = nil
            } label: {
                Text("Use a different number")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

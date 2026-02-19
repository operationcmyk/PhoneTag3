import SwiftUI

struct SetDisplayNameView: View {
    @Bindable var authService: AuthService
    @State private var displayName = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                Text("WHAT'S YOUR NAME?")
                    .font(.title2.weight(.black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text("This is how other players will see you.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            VStack(spacing: 16) {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)

                Button {
                    Task { await authService.createProfile(displayName: displayName.trimmingCharacters(in: .whitespaces)) }
                } label: {
                    Group {
                        if authService.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Let's Go")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(displayName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || authService.isLoading)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }
}

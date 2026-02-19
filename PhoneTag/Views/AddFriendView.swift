import SwiftUI

struct AddFriendView: View {
    let currentUserId: String
    let userRepository: any UserRepositoryProtocol

    @Environment(\.dismiss) private var dismiss
    @State private var phoneNumber = ""
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var didSucceed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone Number")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("+1 555 000 0000", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let msg = resultMessage {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(didSucceed ? .green : .red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Add Friend")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(phoneNumber.isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(phoneNumber.isEmpty || isLoading)

                Spacer()
            }
            .padding()
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isLoading = true
        resultMessage = nil
        let error = await userRepository.addFriend(userId: currentUserId, friendPhone: phoneNumber)
        isLoading = false
        if let error {
            didSucceed = false
            resultMessage = error
        } else {
            didSucceed = true
            resultMessage = "Friend added!"
            phoneNumber = ""
        }
    }
}

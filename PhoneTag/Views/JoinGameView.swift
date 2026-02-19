import SwiftUI

struct JoinGameView: View {
    let userId: String
    let gameRepository: any GameRepositoryProtocol
    let onJoined: (Game) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var normalizedCode: String { code.uppercased().filter { $0.isLetter || $0.isNumber } }
    private var isValidLength: Bool { normalizedCode.count == GameConstants.registrationCodeLength }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                        .onChange(of: code) { _, new in
                            // Cap input at registrationCodeLength characters
                            let filtered = new.uppercased().filter { $0.isLetter || $0.isNumber }
                            if filtered.count > GameConstants.registrationCodeLength {
                                code = String(filtered.prefix(GameConstants.registrationCodeLength))
                            } else {
                                code = filtered
                            }
                            errorMessage = nil
                        }
                } header: {
                    Text("Enter Game Code")
                } footer: {
                    Text("Ask the game creator for their \(GameConstants.registrationCodeLength)-character code.")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task { await joinGame() }
                    }
                    .disabled(!isValidLength || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func joinGame() async {
        isLoading = true
        defer { isLoading = false }

        if let game = await gameRepository.joinGame(byCode: normalizedCode, userId: userId) {
            onJoined(game)
            dismiss()
        } else {
            errorMessage = "No waiting game found with that code. Check the code and try again."
        }
    }
}

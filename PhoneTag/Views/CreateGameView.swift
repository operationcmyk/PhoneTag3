import SwiftUI

struct CreateGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateGameViewModel
    @State private var showingTitlePrompt = false
    let onCreated: () -> Void

    init(userId: String, userRepository: any UserRepositoryProtocol, gameRepository: any GameRepositoryProtocol, onCreated: @escaping () -> Void) {
        _viewModel = State(initialValue: CreateGameViewModel(
            userId: userId,
            userRepository: userRepository,
            gameRepository: gameRepository
        ))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected players header
                if !viewModel.selectedPlayerIds.isEmpty {
                    selectedPlayersBar
                }

                // Friends list
                List(viewModel.friends) { friend in
                    Button {
                        viewModel.togglePlayer(friend.id)
                    } label: {
                        HStack {
                            let colorIndex = viewModel.friends.firstIndex(where: { $0.id == friend.id }) ?? 0
                            Circle()
                                .fill(GameConstants.playerColors[(colorIndex + 1) % GameConstants.playerColors.count])
                                .frame(width: 10, height: 10)

                            Text(friend.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if viewModel.selectedPlayerIds.contains(friend.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Start Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        showingTitlePrompt = true
                    }
                    .bold()
                    .disabled(viewModel.selectedPlayerIds.isEmpty)
                }
            }
            .alert("Game Title", isPresented: $showingTitlePrompt) {
                TextField("e.g. NYC", text: $viewModel.gameTitle)
                    .textInputAutocapitalization(.characters)
                Button("Create") {
                    Task {
                        await viewModel.submitGame()
                        onCreated()
                        dismiss()
                    }
                }
                .disabled(viewModel.gameTitle.isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Max \(GameConstants.gameTitleMaxLength) characters")
            }
            .task {
                await viewModel.loadFriends()
            }
        }
    }

    private var selectedPlayersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Current user (always first)
                playerChip(name: "You", color: GameConstants.playerColors[0], removable: false, id: nil)

                ForEach(Array(viewModel.selectedPlayerIds.enumerated()), id: \.element) { index, playerId in
                    if let friend = viewModel.friends.first(where: { $0.id == playerId }) {
                        let color = GameConstants.playerColors[(index + 1) % GameConstants.playerColors.count]
                        playerChip(name: friend.displayName, color: color, removable: true, id: playerId)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func playerChip(name: String, color: Color, removable: Bool, id: String?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption.bold())
            if removable, let id {
                Button {
                    viewModel.togglePlayer(id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

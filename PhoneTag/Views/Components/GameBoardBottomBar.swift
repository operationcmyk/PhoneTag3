import SwiftUI

struct GameBoardBottomBar: View {
    let playerState: PlayerState
    let playerIds: [String]
    let currentUserId: String
    let allPlayerStates: [String: PlayerState]
    let isArsenalOpen: Bool
    let selectedArsenalItem: ArsenalItem?
    var onToggleArsenal: (() -> Void)?
    var onSelectItem: ((ArsenalItem) -> Void)?
    var onUseItem: (() -> Void)?
    var onOpenStore: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Player status row
            HStack(spacing: 16) {
                ForEach(Array(playerIds.enumerated()), id: \.element) { index, playerId in
                    let state = allPlayerStates[playerId]!
                    let color = GameConstants.playerColors[index % GameConstants.playerColors.count]
                    let label = playerId == currentUserId ? "You" : "P\(index + 1)"

                    PlayerStatusView(
                        label: label,
                        strikes: state.strikes,
                        color: color,
                        isActive: state.isActive
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Arsenal drawer
            ArsenalDrawerView(
                playerState: playerState,
                isOpen: isArsenalOpen,
                selectedItem: selectedArsenalItem,
                onToggle: { onToggleArsenal?() },
                onSelect: { item in onSelectItem?(item) },
                onUse: { onUseItem?() },
                onOpenStore: onOpenStore
            )
        }
    }
}

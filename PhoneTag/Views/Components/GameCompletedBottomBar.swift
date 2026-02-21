import SwiftUI

/// Read-only bottom bar shown when a game has ended.
/// Displays final standings for all players sorted by survival (winner first, then by strikes remaining).
struct GameCompletedBottomBar: View {
    let playerIds: [String]
    let currentUserId: String
    let allPlayerStates: [String: PlayerState]
    let playerNames: [String: String]
    let winner: (id: String, name: String)?

    private var sortedStandings: [(playerId: String, state: PlayerState, rank: Int)] {
        // Sort: active player (winner) first, then by strikes descending (most remaining = survived longer)
        let sorted = playerIds.sorted { a, b in
            let stateA = allPlayerStates[a]!
            let stateB = allPlayerStates[b]!
            if stateA.isActive != stateB.isActive { return stateA.isActive }
            return stateA.strikes > stateB.strikes
        }
        return sorted.enumerated().map { (index, playerId) in
            (playerId: playerId, state: allPlayerStates[playerId]!, rank: index + 1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Final standings header
            HStack {
                Image(systemName: "flag.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Final Standings")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Player standings row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(sortedStandings, id: \.playerId) { standing in
                        let color = GameConstants.playerColors[
                            (playerIds.firstIndex(of: standing.playerId) ?? 0)
                            % GameConstants.playerColors.count
                        ]
                        let isWinner = standing.playerId == winner?.id
                        let name = standing.playerId == currentUserId
                            ? "You"
                            : (playerNames[standing.playerId] ?? "P\(standing.rank)")

                        VStack(spacing: 4) {
                            // Rank + winner trophy
                            HStack(spacing: 2) {
                                if isWinner {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.yellow)
                                } else {
                                    Text("#\(standing.rank)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(name)
                                .font(.caption2.bold())
                                .foregroundStyle(standing.state.isActive ? color : .secondary)
                                .lineLimit(1)

                            HStack(spacing: 2) {
                                ForEach(0..<GameConstants.startingStrikes, id: \.self) { i in
                                    if i < standing.state.strikes {
                                        Image(systemName: "heart.fill")
                                            .font(.caption2)
                                            .foregroundStyle(color)
                                    } else {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Text(standing.state.isActive ? "Survived" : "Eliminated")
                                .font(.system(size: 9))
                                .foregroundStyle(standing.state.isActive ? .green : .secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            isWinner
                                ? Color.yellow.opacity(0.12)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isWinner ? Color.yellow.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .opacity(standing.state.isActive ? 1 : 0.65)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
    }
}

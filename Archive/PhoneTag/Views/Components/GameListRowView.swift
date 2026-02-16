import SwiftUI

struct GameListRowView: View {
    let game: Game
    let currentUserId: String
    let playerNames: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(game.title)
                    .font(.headline)

                Text(game.registrationCode)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                statusBadge
            }

            HStack(spacing: 12) {
                ForEach(Array(sortedPlayerIds.enumerated()), id: \.element) { index, playerId in
                    let state = game.players[playerId]!
                    let color = GameConstants.playerColors[index % GameConstants.playerColors.count]
                    let label = playerId == currentUserId ? "You" : shortName(for: playerId)

                    PlayerStatusView(
                        label: label,
                        strikes: state.strikes,
                        color: color,
                        isActive: state.isActive
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sortedPlayerIds: [String] {
        var ids = Array(game.players.keys)
        ids.sort { a, b in
            if a == currentUserId { return true }
            if b == currentUserId { return false }
            return a < b
        }
        return ids
    }

    private func shortName(for playerId: String) -> String {
        if let name = playerNames[playerId] {
            return String(name.prefix(6))
        }
        return "P\(sortedPlayerIds.firstIndex(of: playerId).map { $0 + 1 } ?? 0)"
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch game.status {
        case .active:
            Label("Active", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .waiting:
            Label("Waiting", systemImage: "clock.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

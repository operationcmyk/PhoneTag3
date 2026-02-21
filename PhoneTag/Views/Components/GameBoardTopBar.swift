import SwiftUI

struct GameBoardTopBar: View {
    let title: String
    let status: GameStatus
    let playerCount: Int
    var winner: (id: String, name: String)? = nil
    var currentUserWon: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)

                Text(statusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.2))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())

                Spacer()

                Label("\(playerCount)", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if status == .completed {
                GameEndedBanner(winner: winner, currentUserWon: currentUserWon)
            }
        }
        .background(.ultraThinMaterial)
    }

    private var statusText: String {
        switch status {
        case .active: "Active"
        case .waiting: "Waiting"
        case .completed: "Game Over"
        }
    }

    private var statusColor: Color {
        switch status {
        case .active: .green
        case .waiting: .orange
        case .completed: .red
        }
    }
}

private struct GameEndedBanner: View {
    let winner: (id: String, name: String)?
    let currentUserWon: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: currentUserWon ? "trophy.fill" : "flag.fill")
                .foregroundStyle(currentUserWon ? .yellow : .secondary)

            if let winner {
                if currentUserWon {
                    Text("You won!")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                } else {
                    Text("\(winner.name) won")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
            } else {
                Text("Game ended — no survivors")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Read-only")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            currentUserWon
                ? Color.yellow.opacity(0.12)
                : Color.red.opacity(0.08)
        )
    }
}

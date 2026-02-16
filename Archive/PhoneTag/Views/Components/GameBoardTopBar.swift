import SwiftUI

struct GameBoardTopBar: View {
    let title: String
    let status: GameStatus
    let playerCount: Int

    var body: some View {
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
        .background(.ultraThinMaterial)
    }

    private var statusText: String {
        switch status {
        case .active: "Active"
        case .waiting: "Waiting"
        case .completed: "Completed"
        }
    }

    private var statusColor: Color {
        switch status {
        case .active: .green
        case .waiting: .orange
        case .completed: .secondary
        }
    }
}

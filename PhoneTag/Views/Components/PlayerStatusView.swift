import SwiftUI

struct PlayerStatusView: View {
    let label: String
    let strikes: Int
    let maxStrikes: Int
    let color: Color
    let isActive: Bool

    init(label: String, strikes: Int, color: Color, isActive: Bool, maxStrikes: Int = GameConstants.startingStrikes) {
        self.label = label
        self.strikes = strikes
        self.color = color
        self.isActive = isActive
        self.maxStrikes = maxStrikes
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(isActive ? color : .secondary)

            HStack(spacing: 2) {
                ForEach(0..<maxStrikes, id: \.self) { i in
                    if i < strikes {
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
        }
        .opacity(isActive ? 1 : 0.5)
    }
}

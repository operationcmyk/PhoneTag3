import SwiftUI

struct TagOverlay: View {
    let tagType: TagType
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onDrop: () -> Void

    private var radiusText: String {
        switch tagType {
        case .basic:     return "~1 block radius"
        case .wideRadius: return "~3-5 block radius"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: tagType == .wideRadius ? "circle.dotted.and.circle" : "scope")
                    .foregroundStyle(tagType == .wideRadius ? GameConstants.arsenalBigTagColor : GameConstants.arsenalTagColor)
                Text(tagType == .wideRadius ? "BIG TAG" : "TAG")
                    .font(.subheadline.weight(.heavy))
                    .tracking(0.5)
                Text("(\(radiusText))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Move the map to aim, then drop your tag")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Button {
                    onDrop()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Drop Tag", systemImage: "scope")
                            .font(.subheadline.bold())
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(GameConstants.arsenalActionRed)
                .disabled(isSubmitting)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .padding()
    }
}

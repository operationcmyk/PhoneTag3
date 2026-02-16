import SwiftUI

struct HomeBaseSetupOverlay: View {
    let hasPlaced: Bool // whether a temp pin is down
    let onUndo: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasPlaced ? "house.fill" : "house")
                .font(.title)
                .foregroundStyle(hasPlaced ? .green : .secondary)

            Text(hasPlaced
                 ? "Home base set! Confirm to start playing."
                 : "Tap the map to place your home base")
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if hasPlaced {
                    Button {
                        onUndo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onConfirm()
                    } label: {
                        Label("Confirm", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .padding()
    }
}

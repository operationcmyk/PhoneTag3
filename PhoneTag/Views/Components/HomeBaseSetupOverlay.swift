import SwiftUI

struct HomeBaseSetupOverlay: View {
    let stepNumber: Int             // 1 or 2
    let hasDroppedPin: Bool         // whether a temp pin is currently down
    let onUndo: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(1...2, id: \.self) { step in
                    Circle()
                        .fill(step <= stepNumber ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(step == stepNumber ? Color.green : Color.clear, lineWidth: 2)
                                .frame(width: 14, height: 14)
                        )
                }
                Text("Safe Zone \(stepNumber) of 2")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: hasDroppedPin ? "shield.fill" : "shield")
                .font(.title)
                .foregroundStyle(hasDroppedPin ? .green : .secondary)

            Text(hasDroppedPin
                 ? "Safe Zone \(stepNumber) pinned! Confirm to lock it in."
                 : "Tap the map to place Safe Zone \(stepNumber)")
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)

            if stepNumber == 1 && !hasDroppedPin {
                Text("Pick a spot you visit often — home, work, a coffee shop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if stepNumber == 2 && !hasDroppedPin {
                Text("Pick a second safe spot far from your first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if hasDroppedPin {
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
                        Label(stepNumber == 2 ? "Confirm & Start" : "Confirm",
                              systemImage: stepNumber == 2 ? "flag.checkered" : "checkmark.circle.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stepNumber == 2 ? .orange : .green)
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

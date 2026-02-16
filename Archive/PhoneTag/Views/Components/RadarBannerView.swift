import SwiftUI

struct RadarBannerView: View {
    let targetName: String
    let timeRemaining: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.body.bold())
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(targetName) is in one of these areas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("\(timeRemaining)s remaining")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

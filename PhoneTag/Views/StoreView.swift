import SwiftUI

struct StoreView: View {
    let gameRepository: any GameRepositoryProtocol
    let userId: String
    let games: [Game]
    var onPurchased: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var confirmProduct: StoreProduct?
    @State private var showingConfirm = false
    @State private var purchaseMessage: String?
    @State private var showingResult = false

    /// Aggregate inventory across all active games (use first active game's state).
    private var currentState: PlayerState? {
        games
            .first { $0.status != .completed && $0.players[userId] != nil }?
            .players[userId]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    inventorySection
                    productsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            .navigationTitle("Arsenal Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.10, green: 0.10, blue: 0.12), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GameConstants.arsenalGold)
                }
            }
            .alert("Confirm Purchase", isPresented: $showingConfirm, presenting: confirmProduct) { product in
                Button("Buy", role: .none) {
                    Task { await purchase(product) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { product in
                Text("Buy \(product.displayName) for \(product.price)?")
            }
            .alert("Purchase Complete", isPresented: $showingResult) {
                Button("OK") {}
            } message: {
                if let msg = purchaseMessage {
                    Text(msg)
                }
            }
        }
    }

    // MARK: - Your Arsenal (inventory)

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hazard stripe accent
            hazardStripe

            Text("YOUR ARSENAL")
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(GameConstants.arsenalGold)
                .padding(.leading, 13)

            HStack(spacing: 12) {
                ForEach(ArsenalItem.allCases) { item in
                    let count = currentState.map { item.count(from: $0) } ?? 0
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(item.legacyColor, lineWidth: 2.5)
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 36, height: 36)
                            Image(systemName: item.icon)
                                .font(.body)
                                .foregroundStyle(item.legacyColor)
                        }
                        Text("\(count)")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(count > 0 ? .white : .white.opacity(0.35))
                        Text(item.displayName)
                            .font(.system(size: 9).weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - Products List

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD TO ARSENAL")
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(GameConstants.arsenalGold)
                .padding(.leading, 13)

            ForEach(StoreProduct.catalog) { product in
                storeCard(for: product)
            }
        }
    }

    private func storeCard(for product: StoreProduct) -> some View {
        HStack(spacing: 12) {
            // Item icon
            ZStack {
                Circle()
                    .stroke(product.item.legacyColor, lineWidth: 3)
                    .frame(width: 48, height: 48)
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                Image(systemName: product.item.icon)
                    .font(.title3)
                    .foregroundStyle(product.item.legacyColor)
            }

            // Name + description
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(product.description)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Price + buy button
            VStack(spacing: 4) {
                Text(product.price)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    confirmProduct = product
                    showingConfirm = true
                } label: {
                    Text("BUY")
                        .font(.caption.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 30)
                        .background(GameConstants.arsenalActionRed)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Hazard Stripe

    private var hazardStripe: some View {
        HStack(spacing: 0) {
            ForEach(0..<30, id: \.self) { i in
                Rectangle()
                    .fill(i.isMultiple(of: 2)
                          ? GameConstants.arsenalGold
                          : Color.black)
                    .frame(width: 14, height: 3)
            }
        }
        .clipShape(Capsule())
        .frame(height: 3)
    }

    // MARK: - Purchase

    private func purchase(_ product: StoreProduct) async {
        await gameRepository.purchaseItem(userId: userId, product: product)
        purchaseMessage = "\(product.displayName) added to your arsenal!"
        showingResult = true
        onPurchased?()
    }
}

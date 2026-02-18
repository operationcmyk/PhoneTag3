import SwiftUI

struct ArsenalDrawerView: View {
    let playerState: PlayerState
    let isOpen: Bool
    let selectedItem: ArsenalItem?
    let onToggle: () -> Void
    let onSelect: (ArsenalItem) -> Void
    let onUse: () -> Void
    var onOpenStore: (() -> Void)?

    // Drawer metrics
    private let collapsedHeight: CGFloat = 56
    private let expandedExtraHeight: CGFloat = 280

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    private var currentOffset: CGFloat {
        if isOpen {
            return max(dragOffset, 0)
        } else {
            return min(dragOffset, 0)
        }
    }

    private var drawerProgress: CGFloat {
        let base: CGFloat = isOpen ? 1 : 0
        let delta = -currentOffset / expandedExtraHeight
        return min(max(base + delta, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Expanded content
            expandedContent
                .frame(height: expandedExtraHeight * drawerProgress, alignment: .top)
                .clipped()
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .ignoresSafeArea(edges: .bottom)
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
        .gesture(dragGesture)
        .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: isOpen)
        .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: selectedItem)
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Button {
            onToggle()
        } label: {
            VStack(spacing: 6) {
                // Hazard stripe accent line (legacy arsenalBg nod)
                HStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in
                        Rectangle()
                            .fill(i.isMultiple(of: 2)
                                  ? GameConstants.arsenalGold
                                  : Color.black)
                            .frame(width: 20, height: 3)
                    }
                }
                .clipShape(Capsule())
                .frame(height: 3)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(GameConstants.arsenalGold)

                    Text("ARSENAL")
                        .font(.subheadline.weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(GameConstants.arsenalGold)

                    Spacer()

                    // Quick count badges for collapsed state
                    if !isOpen {
                        collapsedBadges
                    }

                    Image(systemName: "chevron.up")
                        .font(.caption.bold())
                        .foregroundStyle(GameConstants.arsenalGold.opacity(0.6))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .buttonStyle(.plain)
        .frame(height: collapsedHeight)
    }

    // MARK: - Collapsed Badges

    private var collapsedBadges: some View {
        HStack(spacing: 8) {
            ForEach(ArsenalItem.allCases) { item in
                let count = item.count(from: playerState)
                HStack(spacing: 3) {
                    Image(systemName: item.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(item.legacyColor)
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                }
                .opacity(count > 0 ? 1.0 : 0.35)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.1))

            // Arsenal items — 2x2 grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(ArsenalItem.allCases) { item in
                    ArsenalItemCard(
                        item: item,
                        count: item.count(from: playerState),
                        isAvailable: item.isAvailable(from: playerState),
                        isSelected: selectedItem == item
                    ) {
                        onSelect(item)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Shop button
            if let onOpenStore {
                Button {
                    onOpenStore()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cart.fill")
                            .font(.caption2)
                        Text("SHOP")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.5)
                    }
                    .foregroundStyle(GameConstants.arsenalGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .stroke(GameConstants.arsenalGold.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }

            Spacer(minLength: 8)

            // Use button
            if let selected = selectedItem, selected.isAvailable(from: playerState) {
                useButton(for: selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Use Button

    private func useButton(for item: ArsenalItem) -> some View {
        Button {
            onUse()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.body.bold())
                Text(useButtonText(for: item))
                    .font(.subheadline.weight(.heavy))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(GameConstants.arsenalActionRed)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let threshold: CGFloat = expandedExtraHeight * 0.3

                if isOpen {
                    if value.translation.height > threshold || velocity > 200 {
                        onToggle()
                    }
                } else {
                    if value.translation.height < -threshold || velocity < -200 {
                        onToggle()
                    }
                }
                dragOffset = 0
            }
    }

    // MARK: - Helpers

    private func useButtonText(for item: ArsenalItem) -> String {
        switch item {
        case .basicTag:     return "DROP TAG"
        case .wideRadiusTag: return "DROP BIG TAG"
        case .radar:        return "USE RADAR"
        case .tripwire:     return "PLACE TRIPWIRE"
        }
    }
}

// MARK: - Arsenal Item Card

private struct ArsenalItemCard: View {
    let item: ArsenalItem
    let count: Int
    let isAvailable: Bool
    let isSelected: Bool
    let onTap: () -> Void

    private var accentColor: Color { item.legacyColor }

    var body: some View {
        Button {
            if isAvailable {
                onTap()
            }
        } label: {
            HStack(spacing: 10) {
                // Icon with legacy-style circle ring
                ZStack {
                    Circle()
                        .stroke(accentColor, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(isSelected ? accentColor.opacity(0.25) : Color.white.opacity(0.05))
                        .frame(width: 40, height: 40)

                    Image(systemName: item.icon)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                }

                // Text stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(item.description)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Count badge
                Text("\(count)")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(count > 0 ? accentColor : .white.opacity(0.3))
                    .frame(minWidth: 24)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1.0 : 0.35)
    }
}

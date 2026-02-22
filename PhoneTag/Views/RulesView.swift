import SwiftUI

struct RulesView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // MARK: - Objective
                RulesSection(title: "Objective", icon: "target") {
                    RulesText("Be the last player standing. Eliminate every other player by tagging their location before they tag yours.")
                }

                // MARK: - Lives
                RulesSection(title: "Lives", icon: "heart.fill") {
                    RulesText("Every player starts with **3 lives** (strikes). Lose all 3 and you're eliminated.")
                }

                // MARK: - Tagging
                RulesSection(title: "Tagging", icon: "scope") {
                    RulesText("Open the map, drop a pin where you think an opponent is, and submit your tag.")
                    RulesText("You get **5 free tags per day.** Tags reset at midnight.")
                    RulesBullet(items: [
                        "**Basic tag** — hits within ~80m (about 1 city block)",
                        "**Wide-radius tag** — hits within ~300m (3–5 blocks), purchased from the Arsenal",
                    ])
                    RulesText("If your guess lands within the tag radius of your own location, you take the hit yourself — don't self-bomb.")
                }

                // MARK: - Safe Zones
                RulesSection(title: "Safe Zones", icon: "shield.fill") {
                    RulesText("Players cannot be tagged while inside a safe zone.")
                    RulesBullet(items: [
                        "**Home bases** — you set 2 permanent safe spots before the game begins. Choose wisely.",
                        "**Miss zones** — when a tag misses, the guessed location becomes a temporary safe zone for your target until midnight.",
                        "**Hit zones** — when a tag hits, your target's actual location becomes a permanent safe zone for the rest of the game.",
                    ])
                }

                // MARK: - Home Bases
                RulesSection(title: "Setting Home Bases", icon: "house.fill") {
                    RulesText("Before a game starts, each player must place **2 home bases** — locations you visit regularly, like home, work, or a coffee shop.")
                    RulesText("Pick spots that are far apart for maximum coverage. The game doesn't begin until every player has placed both bases.")
                }

                // MARK: - Tripwires
                RulesSection(title: "Tripwires", icon: "line.diagonal") {
                    RulesText("Tripwires are invisible traps you place on the map. You must **physically be at the location** to place one.")
                    RulesText("If an opponent walks through your tripwire, they lose a life automatically.")
                    RulesText("Tripwires are purchased from the Arsenal.")
                }

                // MARK: - Radar
                RulesSection(title: "Radar", icon: "dot.radiowaves.up.forward") {
                    RulesText("Use a radar ping to reveal the approximate location of a random opponent.")
                    RulesText("The radar shows **two circles** — only one contains your target. Figure out which one and strike fast; the result disappears after 10 seconds.")
                    RulesText("Radars are purchased from the Arsenal.")
                }

                // MARK: - Nudge
                RulesSection(title: "Nudging", icon: "bell.fill") {
                    RulesText("Swipe right on any active game to send a nudge to all other players.")
                    RulesText("After a nudge, every player has **6 hours to open the app.** Anyone who doesn't loses a life — including you if you forget.")
                }

                // MARK: - Inactivity
                RulesSection(title: "Going Offline", icon: "wifi.slash") {
                    RulesText("Your location is updated in the background while a game is active.")
                    RulesText("If you go **48 hours without opening the app**, you automatically lose a life and all co-players are notified.")
                    RulesText("You'll receive a warning notification at the 47-hour mark.")
                }

                // MARK: - Winning
                RulesSection(title: "Winning", icon: "trophy.fill") {
                    RulesText("The last player with at least 1 life remaining wins the game.")
                }

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Reusable Components

private struct RulesSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.orange)
                    .fontWeight(.semibold)
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            content()
        }
    }
}

private struct RulesText: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RulesBullet: View {
    let items: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.orange)
                        .fontWeight(.bold)
                    Text(item)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RulesView()
    }
}

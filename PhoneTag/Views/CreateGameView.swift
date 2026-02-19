import SwiftUI
import MessageUI

struct CreateGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateGameViewModel
    @State private var showingTitlePrompt = false
    @State private var showingShareCode = false
    let onCreated: () -> Void

    init(
        userId: String,
        userRepository: any UserRepositoryProtocol,
        gameRepository: any GameRepositoryProtocol,
        contactsService: ContactsService,
        onCreated: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: CreateGameViewModel(
            userId: userId,
            userRepository: userRepository,
            gameRepository: gameRepository,
            contactsService: contactsService
        ))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selectedPlayersBar

                if viewModel.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        appFriendsSection
                        appContactsSection
                        offAppContactsSection
                    }
                }
            }
            .navigationTitle("Start Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") { showingTitlePrompt = true }
                        .bold()
                }
            }
            .alert("Game Title", isPresented: $showingTitlePrompt) {
                TextField("e.g. NYC", text: $viewModel.gameTitle)
                    .textInputAutocapitalization(.characters)
                Button("Create") {
                    Task {
                        await viewModel.submitGame()
                        onCreated()
                        showingShareCode = true
                    }
                }
                .disabled(viewModel.gameTitle.isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Max \(GameConstants.gameTitleMaxLength) characters")
            }
            .sheet(isPresented: $showingShareCode, onDismiss: { dismiss() }) {
                if let game = viewModel.createdGame {
                    GameCodeShareView(
                        game: game,
                        preselectedPhones: viewModel.selectedInvitePhones
                    )
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var appFriendsSection: some View {
        if !viewModel.appFriends.isEmpty {
            Section {
                ForEach(Array(viewModel.appFriends.enumerated()), id: \.element.id) { index, friend in
                    playerRow(
                        name: friend.displayName,
                        subtitle: nil,
                        color: GameConstants.playerColors[(index + 1) % GameConstants.playerColors.count],
                        isSelected: viewModel.selectedPlayerIds.contains(friend.id),
                        badge: nil
                    ) {
                        viewModel.togglePlayer(friend.id)
                    }
                }
            } header: {
                Label("Friends on PhoneTag", systemImage: "person.2.fill")
            }
        }
    }

    @ViewBuilder
    private var appContactsSection: some View {
        if !viewModel.appContacts.isEmpty {
            Section {
                ForEach(viewModel.appContacts) { contact in
                    playerRow(
                        name: contact.displayName,
                        subtitle: contact.phoneNumber,
                        color: .gray,
                        isSelected: viewModel.selectedPlayerIds.contains(contact.id),
                        badge: "PhoneTag"
                    ) {
                        viewModel.togglePlayer(contact.id)
                    }
                }
            } header: {
                Label("Contacts on PhoneTag", systemImage: "person.crop.circle.badge.checkmark")
            } footer: {
                Text("These contacts use PhoneTag but aren't your friends yet. Selecting them adds them to the game.")
            }
        }
    }

    @ViewBuilder
    private var offAppContactsSection: some View {
        if !viewModel.offAppContacts.isEmpty {
            Section {
                ForEach(viewModel.offAppContacts) { contact in
                    inviteRow(contact: contact)
                }
            } header: {
                Label("Invite via Text", systemImage: "message")
            } footer: {
                Text("These contacts aren't on PhoneTag yet. Select them to send a text invite with your game code after creating.")
            }
        } else if viewModel.contactsPermissionDenied {
            Section {
                Label("Allow contacts access in Settings to see your contacts here.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } header: {
                Label("Invite via Text", systemImage: "message")
            }
        }
    }

    // MARK: - Row helpers

    private func playerRow(
        name: String,
        subtitle: String?,
        color: Color,
        isSelected: Bool,
        badge: String?,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? color : color.opacity(0.3))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? color : .secondary)
            }
        }
    }

    private func inviteRow(contact: DeviceContact) -> some View {
        let isSelected = viewModel.selectedInviteContacts.contains(contact.id)
        return Button {
            viewModel.toggleInviteContact(contact.id)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Color.blue.opacity(0.6) : Color.secondary.opacity(0.2))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .foregroundStyle(.primary)
                    if let phone = contact.phoneNumbers.first {
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
        }
    }

    // MARK: - Selected players bar

    private var selectedPlayersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                playerChip(name: "You", color: GameConstants.playerColors[0], removable: false, id: nil)

                ForEach(Array(viewModel.selectedPlayerIds.enumerated()), id: \.element) { index, playerId in
                    let name = viewModel.appFriends.first(where: { $0.id == playerId })?.displayName
                        ?? viewModel.appContacts.first(where: { $0.id == playerId })?.displayName
                        ?? "Player"
                    let color = GameConstants.playerColors[(index + 1) % GameConstants.playerColors.count]
                    playerChip(name: name, color: color, removable: true, id: playerId)
                }

                ForEach(viewModel.offAppContacts.filter { viewModel.selectedInviteContacts.contains($0.id) }) { contact in
                    inviteChip(name: contact.displayName)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func playerChip(name: String, color: Color, removable: Bool, id: String?) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption.bold())
            if removable, let id {
                Button { viewModel.togglePlayer(id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func inviteChip(name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "message.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
            Text(name).font(.caption.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Game Code Share Sheet

struct GameCodeShareView: View {
    let game: Game
    let preselectedPhones: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var showingMessageCompose = false
    @State private var copied = false

    private var shareMessage: String {
        "Join my Phone Tag game \"\(game.title)\"! Use code: \(game.registrationCode)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Game Created!")
                        .font(.title2.bold())
                    Text("Share this code with anyone you want to invite.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Text(game.registrationCode)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button {
                        UIPasteboard.general.string = game.registrationCode
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? "Copied!" : "Copy Code",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                    .foregroundStyle(copied ? .green : .secondary)
                    .animation(.easeInOut(duration: 0.2), value: copied)
                }

                VStack(spacing: 12) {
                    // Text/iMessage — shown first if contacts were preselected
                    if MFMessageComposeViewController.canSendText() {
                        Button {
                            showingMessageCompose = true
                        } label: {
                            Label(
                                preselectedPhones.isEmpty ? "Send via iMessage / SMS" : "Text Your Invites",
                                systemImage: "message.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(preselectedPhones.isEmpty ? Color(.secondarySystemGroupedBackground) : .blue)
                            .foregroundStyle(preselectedPhones.isEmpty ? Color.primary : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 32)
                    }

                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(preselectedPhones.isEmpty ? .blue : Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(preselectedPhones.isEmpty ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationTitle(game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [shareMessage])
            }
            .sheet(isPresented: $showingMessageCompose) {
                MessageComposeView(
                    recipients: preselectedPhones,
                    body: shareMessage
                )
            }
            .onAppear {
                // Auto-open message compose if contacts were preselected
                if !preselectedPhones.isEmpty && MFMessageComposeViewController.canSendText() {
                    showingMessageCompose = true
                }
            }
        }
    }
}

// MARK: - MFMessageComposeViewController wrapper

struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients.isEmpty ? nil : recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

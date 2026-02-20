import SwiftUI
import MapKit

struct GameBoardView: View {
    @Bindable var viewModel: GameBoardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingStore = false
    @State private var showingLeaveConfirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen map
            GameMapView(
                cameraPosition: $viewModel.cameraPosition,
                homeBase: viewModel.myPlayerState?.homeBase1,
                homeBase2: viewModel.mySafeZone2,
                homeBaseColor: viewModel.myColor,
                otherPlayersHomeBases: viewModel.otherPlayersHomeBases,
                tempHomeBase: viewModel.tempHomeBase,
                safeZonePlacementNumber: viewModel.safeZonePlacementNumber,
                safeBases: viewModel.myPlayerState?.safeBases ?? [],
                tags: viewModel.visibleTags,
                radarResult: viewModel.showingRadar ? viewModel.radarResult : nil,
                myTripwires: viewModel.myPlayerState?.tripwires ?? [],
                isSettingBase: viewModel.isSettingHomeBase,
                isTagging: viewModel.isTagging,
                onTap: { coordinate in
                    if viewModel.isSettingHomeBase {
                        viewModel.placeHomeBase(at: coordinate)
                    }
                },
                onCenterChanged: { center in
                    viewModel.visibleMapCenter = center
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                // Radar banner (top)
                if viewModel.showingRadar, let radar = viewModel.radarResult {
                    RadarBannerView(
                        targetName: radar.targetName,
                        timeRemaining: viewModel.radarTimeRemaining,
                        onDismiss: { viewModel.dismissRadar() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if viewModel.isSettingHomeBase {
                    HomeBaseSetupOverlay(
                        stepNumber: viewModel.safeZonePlacementNumber,
                        hasDroppedPin: viewModel.hasDroppedTempPin,
                        onUndo: { viewModel.undoPlacement() },
                        onConfirm: {
                            Task { await viewModel.saveHomeBase() }
                        }
                    )
                } else if viewModel.isTagging {
                    TagOverlay(
                        tagType: viewModel.selectedArsenalItem == .wideRadiusTag ? .wideRadius : .basic,
                        isSubmitting: viewModel.isSubmittingTag,
                        onCancel: { viewModel.cancelTagging() },
                        onDrop: {
                            guard let center = viewModel.visibleMapCenter
                                    ?? viewModel.locationService.currentLocation?.coordinate else { return }
                            Task {
                                await viewModel.submitTag(at: center)
                            }
                        }
                    )
                } else if let state = viewModel.myPlayerState {
                    GameBoardBottomBar(
                        playerState: state,
                        playerIds: viewModel.sortedPlayerIds,
                        currentUserId: viewModel.userId,
                        allPlayerStates: viewModel.game.players,
                        isArsenalOpen: viewModel.isArsenalOpen,
                        selectedArsenalItem: viewModel.selectedArsenalItem,
                        onToggleArsenal: { viewModel.toggleArsenal() },
                        onSelectItem: { item in viewModel.selectArsenalItem(item) },
                        onUseItem: { viewModel.useSelectedItem() },
                        onOpenStore: { showingStore = true }
                    )
                }
            }
        }
        .safeAreaInset(edge: .top) {
            GameBoardTopBar(
                title: viewModel.game.title,
                status: viewModel.game.status,
                playerCount: viewModel.game.players.count
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingLeaveConfirm = true
                } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Leave Game?", isPresented: $showingLeaveConfirm, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    await viewModel.leaveGame()
                }
            }
        } message: {
            Text("You'll be removed from \(viewModel.game.title). This can't be undone.")
        }
        .onChange(of: viewModel.didLeave) {
            if viewModel.didLeave { dismiss() }
        }
        .task {
            await viewModel.loadPlayerNames()
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.locationService.locationUpdateCount) {
            viewModel.centerOnUserIfNeeded()
        }
        .onChange(of: viewModel.locationService.lastTriggeredRegionId) { _, regionId in
            // A tripwire geofence was crossed — process the hit
            if let regionId {
                viewModel.handleTripwireTrigger(regionId)
            }
        }
        .sheet(isPresented: $showingStore) {
            StoreView(
                gameRepository: viewModel.gameRepository,
                userId: viewModel.userId,
                games: [viewModel.game]
            ) {
                Task { await viewModel.refreshGame() }
            }
        }
        .alert(tagResultTitle(viewModel.tagResult), isPresented: $viewModel.showingTagResult) {
            Button("OK") {
                viewModel.tagResult = nil
            }
        } message: {
            if let result = viewModel.tagResult {
                Text(tagResultMessage(result))
            }
        }
    }

    private func tagResultTitle(_ result: TagResult?) -> String {
        guard let result else { return "Tag Result" }
        if case .hit(_, _, let name) = result, name == viewModel.playerNames[viewModel.userId] ?? "" {
            return "⚡ Tripwire!"
        }
        return "Tag Result"
    }

    private func tagResultMessage(_ result: TagResult) -> String {
        switch result {
        case .hit(_, _, let targetName):
            // Tripwire hits target the current user; taggerName is "tripwire"
            if targetName == viewModel.playerNames[viewModel.userId] {
                return "You walked into a tripwire and lost a life! -1 strike."
            }
            return "Hit - \(targetName)"
        case .miss(let distance):
            return "Miss. Closest target was \(Int(distance))m away."
        case .blocked(let reason):
            switch reason {
            case .homeBase:
                return "Blocked — target is at their home base."
            case .safeBase:
                return "Blocked — target is at a safe base."
            case .outOfTags:
                return "You're out of tags for today."
            case .playerEliminated:
                return "That player is already eliminated."
            }
        }
    }
}

# Phone Tag - Essential Code Snippets

Quick reference for common implementation patterns extracted from legacy analysis.

---

## Data Models

### User Session
```swift
// Modern equivalent of PTStaticInfo singleton
@Observable
class UserSession {
    static let shared = UserSession()

    var userId: String?
    var username: String = ""
    var fullName: String = ""
    var email: String = ""
    var activeGameId: String?
    var arsenal: Arsenal = Arsenal()
    var version: String = ""

    private init() {
        loadFromUserDefaults()
    }

    func logout() {
        userId = nil
        username = ""
        fullName = ""
        email = ""
        activeGameId = nil

        clearUserDefaults()
        NotificationCenter.default.post(name: .userLoggedOut, object: nil)
    }

    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "userSession"),
           let decoded = try? JSONDecoder().decode(UserSessionData.self, from: data) {
            self.userId = decoded.userId
            self.username = decoded.username
            self.fullName = decoded.fullName
            self.email = decoded.email
        }
    }

    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "userSession")
    }
}
```

### Game Model
```swift
struct Game: Identifiable, Codable, Sendable {
    let id: String
    let createdAt: Date
    var players: [String: PlayerState]
    let createdBy: String
    var status: GameStatus
    var startedAt: Date?
    var endedAt: Date?
    var winner: String?
    let registrationCode: String
    let gameType: String

    enum GameStatus: String, Codable {
        case waiting    // Waiting for players to set home bases
        case active     // Game in progress
        case completed  // Game ended
    }
}

struct PlayerState: Codable {
    var strikes: Int = 3
    var tagsRemainingToday: Int = 5
    var homeBase1: CLLocationCoordinate2D?
    var homeBase2: CLLocationCoordinate2D?
    var safeBases: [SafeBase] = []
    var isActive: Bool = true
    var tripwires: [String] = [] // Tripwire IDs
    var arsenal: PlayerArsenal = PlayerArsenal()

    var homeBasesComplete: Bool {
        homeBase1 != nil && homeBase2 != nil
    }
}

struct PlayerArsenal: Codable {
    var basicBombs: Int = 5
    var wideRadiusBombs: Int = 0
    var tripwires: Int = 0
    var extraBases: Int = 0
}
```

### Tag/Bomb Model
```swift
struct Tag: Identifiable, Codable {
    let id: String
    let gameId: String
    let fromUserId: String
    let guessedLocation: CLLocationCoordinate2D
    let timestamp: Date
    let tagType: TagType
    var results: [TagResult] = []

    enum TagType: String, Codable {
        case basic          // ~80m radius
        case wideRadius     // ~300m radius
    }
}

struct TagResult: Codable {
    let targetUserId: String
    let resultType: ResultType
    let distance: Double
    let actualLocation: CLLocationCoordinate2D?
    let newStrikes: Int?

    enum ResultType: String, Codable {
        case hit
        case miss
        case blocked
    }

    var isHit: Bool { resultType == .hit }
}
```

### Safe Base Model
```swift
struct SafeBase: Identifiable, Codable {
    let id: String
    let location: CLLocationCoordinate2D
    let createdAt: Date
    let type: SafeBaseType
    let expiresAt: Date?

    enum SafeBaseType: String, Codable {
        case homeBase       // Set at game start
        case missedTag      // Expires at midnight
        case hitTag         // Permanent for game duration
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}
```

### CLLocationCoordinate2D Extensions
```swift
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

extension CLLocationCoordinate2D: @unchecked Sendable {}
```

---

## Services

### Location Service
```swift
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus

    private let locationManager = CLLocationManager()
    private var lastUpdateTime: Date?

    private override init() {
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 100 // 100 meters
    }

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        // Only call when game starts
        locationManager.requestAlwaysAuthorization()
    }

    func startUpdating() {
        locationManager.startUpdatingLocation()
    }

    func startMonitoringSignificantChanges() {
        // Battery-efficient background monitoring
        locationManager.startMonitoringSignificantLocationChanges()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    // Geofencing for tripwires
    func monitorRegion(identifier: String, center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        let region = CLCircularRegion(
            center: center,
            radius: min(radius, locationManager.maximumRegionMonitoringDistance),
            identifier: identifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)
    }

    func stopMonitoringRegion(identifier: String) {
        guard let region = locationManager.monitoredRegions
            .first(where: { $0.identifier == identifier }) else { return }
        locationManager.stopMonitoring(for: region)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location

            // Update Firebase if enough time has passed
            if shouldUpdateFirebase() {
                await updateLocationInFirebase(location)
                lastUpdateTime = Date()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        Task { @MainActor in
            await handleTripwireEntry(region.identifier)
        }
    }

    private func shouldUpdateFirebase() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) >= 300 // 5 minutes
    }

    private func updateLocationInFirebase(_ location: CLLocation) async {
        // Implement Firebase update
    }

    private func handleTripwireEntry(_ tripwireId: String) async {
        // Call Cloud Function
    }
}
```

### Firebase Service
```swift
actor FirebaseService {
    static let shared = FirebaseService()

    private let database = Database.database()
    private let auth = Auth.auth()

    private init() {}

    // MARK: - Game Operations

    func createGame(playerIds: [String], gameName: String?) async throws -> Game {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("createGame")

        let data: [String: Any] = [
            "playerIds": playerIds,
            "gameName": gameName ?? ""
        ]

        let result = try await callable.call(data)

        guard let gameData = result.data as? [String: Any],
              let gameId = gameData["gameId"] as? String else {
            throw GameError.invalidResponse
        }

        return try await fetchGame(gameId)
    }

    func fetchGame(_ gameId: String) async throws -> Game {
        let ref = database.reference().child("games/\(gameId)")
        let snapshot = try await ref.getData()
        return try snapshot.data(as: Game.self)
    }

    func observeGame(_ gameId: String) -> AsyncStream<Game> {
        AsyncStream { continuation in
            let ref = database.reference().child("games/\(gameId)")

            let handle = ref.observe(.value) { snapshot in
                guard let game = try? snapshot.data(as: Game.self) else { return }
                continuation.yield(game)
            }

            continuation.onTermination = { @Sendable _ in
                ref.removeObserver(withHandle: handle)
            }
        }
    }

    func setHomeBase(_ gameId: String, userId: String, base: CLLocationCoordinate2D, baseNumber: Int) async throws {
        let ref = database.reference()
            .child("games/\(gameId)/players/\(userId)/homeBase\(baseNumber)")

        let locationData: [String: Any] = [
            "latitude": base.latitude,
            "longitude": base.longitude
        ]

        try await ref.setValue(locationData)
    }

    // MARK: - Tag Operations

    func validateTag(gameId: String, guessedLocation: CLLocationCoordinate2D, tagType: Tag.TagType) async throws -> [TagResult] {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("validateTag")

        let data: [String: Any] = [
            "gameId": gameId,
            "guessedLocation": [
                "latitude": guessedLocation.latitude,
                "longitude": guessedLocation.longitude
            ],
            "tagType": tagType.rawValue
        ]

        let result = try await callable.call(data)

        guard let resultData = result.data as? [String: Any],
              let results = resultData["results"] as? [[String: Any]] else {
            throw GameError.invalidResponse
        }

        return try results.map { dict in
            let targetId = dict["targetUserId"] as! String
            let resultType = Tag.TagResult.ResultType(rawValue: dict["resultType"] as! String)!
            let distance = dict["distance"] as! Double

            return TagResult(
                targetUserId: targetId,
                resultType: resultType,
                distance: distance,
                actualLocation: nil,
                newStrikes: dict["newStrikes"] as? Int
            )
        }
    }

    // MARK: - Location Updates

    func updateLocation(_ location: CLLocation) async throws {
        guard let userId = auth.currentUser?.uid else { return }

        let ref = database.reference().child("locations/\(userId)/current")

        let locationData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "timestamp": ServerValue.timestamp()
        ]

        try await ref.setValue(locationData)
    }
}
```

---

## Views

### Home View
```swift
struct HomeView: View {
    @State private var games: [Game] = []
    @State private var showingJoinModal = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Image("background")
                    .resizable()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Start Game Button
                    Button(action: { navigateToStartGame() }) {
                        Image("startAGame")
                            .resizable()
                            .frame(height: 117)
                    }

                    // Games List or Logo
                    if games.isEmpty {
                        Spacer()
                        Image("ptLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 284, height: 237)
                        Spacer()
                    } else {
                        List {
                            ForEach(games) { game in
                                GameListRow(game: game)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable {
                            await loadGames()
                        }
                    }

                    // Bottom Navigation
                    HStack(spacing: 0) {
                        Spacer()

                        Button(action: { showArsenal() }) {
                            Image("arsenal")
                                .resizable()
                                .frame(width: 111, height: 56)
                        }

                        Spacer()

                        Button(action: { showSettings() }) {
                            Image("settings")
                                .resizable()
                                .frame(width: 45, height: 38)
                        }
                        .padding(.trailing, 10)
                    }
                    .frame(height: 56)
                    .background(
                        Image("bottomBox")
                            .resizable()
                    )
                }
            }
            .sheet(isPresented: $showingJoinModal) {
                JoinGameView()
            }
            .onAppear {
                Task {
                    await loadGames()
                }
            }
        }
    }

    private func loadGames() async {
        isLoading = true
        defer { isLoading = false }

        do {
            games = try await FirebaseService.shared.fetchActiveGames()
        } catch {
            print("Error loading games: \(error)")
        }
    }
}
```

### Join Game Modal
```swift
struct JoinGameView: View {
    @Environment(\.dismiss) var dismiss
    @State private var code = ["", "", "", "", "", ""]
    @FocusState private var focusedField: Int?

    var body: some View {
        ZStack {
            Image("joinAGame")
                .resizable()
                .frame(height: 383)

            VStack(spacing: 20) {
                Text("Enter Game Code")
                    .font(.headline)

                // 6 code input fields
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { index in
                        CodeTextField(
                            text: $code[index],
                            isFocused: focusedField == index
                        )
                        .focused($focusedField, equals: index)
                        .frame(width: 36, height: 45)
                        .onChange(of: code[index]) { _, newValue in
                            if newValue.count == 1 && index < 5 {
                                focusedField = index + 1
                            }
                        }
                    }
                }

                HStack {
                    Button(action: { dismiss() }) {
                        Image("cancelCode")
                    }

                    Spacer()

                    Button(action: { joinGame() }) {
                        Image("joinButton")
                    }
                    .disabled(code.joined().count < 6)
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(height: 448)
        .onAppear {
            focusedField = 0
        }
    }

    private func joinGame() {
        let codeString = code.joined()
        // Call Firebase to join game
    }
}

struct CodeTextField: View {
    @Binding var text: String
    let isFocused: Bool

    var body: some View {
        TextField("*", text: $text)
            .multilineTextAlignment(.center)
            .textCase(.uppercase)
            .font(.system(size: 16, weight: .bold))
            .frame(width: 36, height: 45)
            .background(Color.white)
            .cornerRadius(4)
            .onChange(of: text) { _, newValue in
                if newValue.count > 1 {
                    text = String(newValue.prefix(1))
                }
            }
    }
}
```

### Game Board View
```swift
struct GameBoardView: View {
    let game: Game
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var placementMode: PlacementMode?
    @State private var selectedItem: ArsenalItem?

    enum PlacementMode {
        case bomb(TagType)
        case homeBase(Int)
        case tripwire
    }

    var body: some View {
        ZStack {
            // Map
            Map(position: $cameraPosition) {
                UserAnnotation()

                // Home bases
                ForEach(game.currentPlayer.homeBases) { base in
                    Annotation("Home Base", coordinate: base.location) {
                        HomeBaseView()
                    }
                }

                // Safe bases
                ForEach(game.currentPlayer.safeBases) { base in
                    Annotation("Safe Base", coordinate: base.location) {
                        SafeBaseView(expiresAt: base.expiresAt)
                    }
                }

                // Other players' bombs (radius circles)
                ForEach(game.visibleBombs) { bomb in
                    MapCircle(center: bomb.location, radius: bomb.radius)
                        .foregroundStyle(.red.opacity(0.2))
                        .stroke(.red, lineWidth: 2)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }

            // Crosshairs overlay (when placing)
            if placementMode != nil {
                VStack {
                    Spacer()

                    Image("crosshairs")
                        .resizable()
                        .frame(width: 100, height: 100)

                    Spacer()

                    // Drop button
                    Button(action: { dropItem() }) {
                        Text("DROP")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 120)
                }
            }

            // Arsenal carousel (bottom)
            VStack {
                Spacer()

                ArsenalCarousel(
                    items: game.currentPlayer.arsenal,
                    onSelect: { item in
                        enterPlacementMode(for: item)
                    }
                )
                .frame(height: 100)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func enterPlacementMode(for item: ArsenalItem) {
        selectedItem = item
        placementMode = .bomb(item.tagType)
    }

    private func dropItem() {
        guard let mode = placementMode else { return }

        // Get center coordinate of map
        let centerCoordinate = getCenterCoordinate()

        switch mode {
        case .bomb(let tagType):
            Task {
                await dropBomb(at: centerCoordinate, type: tagType)
            }
        case .homeBase(let number):
            Task {
                await setHomeBase(at: centerCoordinate, number: number)
            }
        case .tripwire:
            Task {
                await placeTripwire(at: centerCoordinate)
            }
        }

        placementMode = nil
        selectedItem = nil
    }

    private func getCenterCoordinate() -> CLLocationCoordinate2D {
        // Get map's center coordinate
        // Implementation depends on MapKit API
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    private func dropBomb(at location: CLLocationCoordinate2D, type: TagType) async {
        do {
            let results = try await FirebaseService.shared.validateTag(
                gameId: game.id,
                guessedLocation: location,
                tagType: type
            )
            showResults(results)
        } catch {
            print("Error dropping bomb: \(error)")
        }
    }
}
```

### Arsenal Carousel
```swift
struct ArsenalCarousel: View {
    let items: [ArsenalItem]
    let onSelect: (ArsenalItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    ArsenalItemCell(item: item)
                        .onTapGesture {
                            if item.quantity > 0 {
                                onSelect(item)
                            }
                        }
                        .opacity(item.quantity > 0 ? 1.0 : 0.5)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ArsenalItemCell: View {
    let item: ArsenalItem

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: item.iconName)
                .font(.system(size: 32))
                .foregroundColor(item.color)

            Text(item.name)
                .font(.caption)

            Text("x \(item.quantity)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 80, height: 80)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

struct ArsenalItem: Identifiable {
    let id = UUID()
    let name: String
    let iconName: String
    let color: Color
    let quantity: Int
    let tagType: TagType?
}
```

---

## Utilities

### Distance Calculator
```swift
extension CLLocation {
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let location = CLLocation(latitude: coordinate.latitude,
                                 longitude: coordinate.longitude)
        return distance(from: location)
    }
}

// Alternative: Haversine formula implementation
func calculateDistance(
    from coord1: CLLocationCoordinate2D,
    to coord2: CLLocationCoordinate2D
) -> Double {
    let earthRadius = 6371000.0 // meters

    let lat1 = coord1.latitude * .pi / 180
    let lat2 = coord2.latitude * .pi / 180
    let deltaLat = (coord2.latitude - coord1.latitude) * .pi / 180
    let deltaLon = (coord2.longitude - coord1.longitude) * .pi / 180

    let a = sin(deltaLat/2) * sin(deltaLat/2) +
            cos(lat1) * cos(lat2) *
            sin(deltaLon/2) * sin(deltaLon/2)

    let c = 2 * atan2(sqrt(a), sqrt(1-a))

    return earthRadius * c
}
```

### Outlined Text (Legacy Style)
```swift
struct OutlinedText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight

    var body: some View {
        ZStack {
            // Black outline
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.black)
                .offset(x: -1, y: -1)

            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.black)
                .offset(x: 1, y: -1)

            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.black)
                .offset(x: -1, y: 1)

            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.black)
                .offset(x: 1, y: 1)

            // White fill
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.white)
        }
    }
}
```

### Constants
```swift
enum GameConstants {
    // Tag radii
    static let basicTagRadius: CLLocationDistance = 80      // ~1 block
    static let wideRadiusTagRadius: CLLocationDistance = 300 // ~3-5 blocks

    // Game settings
    static let startingStrikes = 3
    static let dailyTagLimit = 5
    static let homeBaseRadius: CLLocationDistance = 50
    static let safeBaseRadius: CLLocationDistance = 50

    // Location settings
    static let locationUpdateDistance: CLLocationDistance = 100 // meters
    static let locationUpdateInterval: TimeInterval = 300        // 5 minutes
    static let locationAccuracy = kCLLocationAccuracyNearestTenMeters

    // UI dimensions
    static let gameRowHeight: CGFloat = 234
    static let bottomBarHeight: CGFloat = 56
    static let statusBarHeight: CGFloat = 32
    static let startGameBannerHeight: CGFloat = 117
}
```

---

## Cloud Functions

### Validate Tag
```javascript
// functions/src/validateTag.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.database();

export const validateTag = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const userId = context.auth.uid;
  const { gameId, guessedLocation, tagType } = data;

  // Validate inputs
  if (!gameId || !guessedLocation || !tagType) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Get game state
  const gameSnap = await db.ref(`games/${gameId}`).once('value');
  const game = gameSnap.val();

  if (!game) {
    throw new functions.https.HttpsError('not-found', 'Game not found');
  }

  const playerState = game.players[userId];

  // Check tags remaining
  if (playerState.tagsRemainingToday <= 0) {
    throw new functions.https.HttpsError('failed-precondition', 'No tags remaining today');
  }

  const results = [];

  // Check all active players
  for (const [targetId, targetState] of Object.entries(game.players)) {
    if (targetId === userId || !targetState.isActive) continue;

    // Get target's current location
    const locationSnap = await db.ref(`locations/${targetId}/current`).once('value');
    const targetLocation = locationSnap.val();

    if (!targetLocation) continue;

    // Calculate distance
    const distance = calculateDistance(
      guessedLocation.latitude,
      guessedLocation.longitude,
      targetLocation.latitude,
      targetLocation.longitude
    );

    // Determine radius based on tag type
    const radius = tagType === 'basic' ? 80 : 300;

    // Check if in safe base
    const inSafeBase = await checkSafeBases(targetLocation, targetState);

    if (inSafeBase) {
      results.push({
        targetUserId: targetId,
        resultType: 'blocked',
        distance: distance
      });
    } else if (distance <= radius) {
      // HIT!
      const newStrikes = Math.max(0, targetState.strikes - 1);

      // Update strikes
      await db.ref(`games/${gameId}/players/${targetId}/strikes`).set(newStrikes);

      // Check if eliminated
      if (newStrikes === 0) {
        await db.ref(`games/${gameId}/players/${targetId}/isActive`).set(false);
      }

      // Create permanent safe base
      await createSafeBase(gameId, targetId, targetLocation, 'hitTag', null);

      results.push({
        targetUserId: targetId,
        resultType: 'hit',
        distance: distance,
        newStrikes: newStrikes
      });

      // Send notification
      await sendNotification(targetId, {
        title: 'Tagged!',
        body: `You were hit! ${newStrikes} strikes remaining.`,
        type: 'tagged',
        gameId: gameId
      });
    } else {
      // MISS - create temporary safe base
      await createSafeBase(gameId, targetId, guessedLocation, 'missedTag', getNextMidnight());

      results.push({
        targetUserId: targetId,
        resultType: 'miss',
        distance: distance
      });
    }
  }

  // Decrement tags remaining
  await db.ref(`games/${gameId}/players/${userId}/tagsRemainingToday`)
    .transaction(count => Math.max(0, count - 1));

  return { results };
});

function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000; // Earth radius in meters
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;

  const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ/2) * Math.sin(Δλ/2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

  return R * c;
}

async function checkSafeBases(location: any, playerState: any): Promise<boolean> {
  const bases = [
    playerState.homeBase1,
    playerState.homeBase2,
    ...(playerState.safeBases || []).map(b => b.location)
  ];

  for (const base of bases) {
    if (!base) continue;

    const distance = calculateDistance(
      location.latitude,
      location.longitude,
      base.latitude,
      base.longitude
    );

    if (distance <= 50) return true;
  }

  return false;
}

async function createSafeBase(
  gameId: string,
  userId: string,
  location: any,
  type: string,
  expiresAt: number | null
) {
  const safeBaseRef = db.ref(`games/${gameId}/players/${userId}/safeBases`).push();

  await safeBaseRef.set({
    id: safeBaseRef.key,
    location: location,
    type: type,
    createdAt: admin.database.ServerValue.TIMESTAMP,
    expiresAt: expiresAt
  });
}

function getNextMidnight(): number {
  const now = new Date();
  const midnight = new Date(now);
  midnight.setHours(24, 0, 0, 0);
  return midnight.getTime();
}

async function sendNotification(userId: string, payload: any) {
  // Get user's push tokens
  const tokensSnap = await db.ref(`users/${userId}/pushTokens`).once('value');
  const tokens = tokensSnap.val();

  if (!tokens) return;

  const message = {
    notification: {
      title: payload.title,
      body: payload.body
    },
    data: payload,
    tokens: Object.values(tokens).map(t => t.token)
  };

  await admin.messaging().sendMulticast(message);
}
```

---

These snippets provide copy-paste starting points for the most critical parts of the app. Adapt as needed based on your specific requirements.

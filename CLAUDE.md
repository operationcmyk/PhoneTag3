# Phone Tag - iOS Game Development with Claude Code

## Project Context
Phone Tag is a real-time, location-based multiplayer game where players tag each other by guessing locations throughout the day. This is a ground-up build using modern iOS technologies.

**CRITICAL**: There is a legacy 2012 iOS codebase located at `../phone-tag-legacy/` that contains the original UI/UX design. Before implementing any UI screen, you MUST analyze the corresponding legacy view to match the design, layout, and user experience as closely as possible.

## How to Work with Claude Code on This Project

### Development Approach
- **Legacy UI/UX First**: Always read the legacy view controller before implementing modern SwiftUI equivalent
- **Plan Mode First**: For major features, start in Plan Mode to analyze approach before coding
- **Incremental Development**: Build and test one feature at a time following the phases below
- **Server-Side Validation**: Always implement Cloud Functions before client features
- **Test-Driven**: Write tests for game logic before implementation

### Legacy Codebase Integration
The original 2012 codebase is in Objective-C with UIKit. Your job is to:
1. **Analyze** the legacy UI before implementing each screen
2. **Match** the layout, button placement, visual hierarchy, and user flow
3. **Modernize** by converting Objective-C/UIKit to Swift/SwiftUI
4. **Document** any necessary deviations from the original design

**Legacy Code Location**: `../phone-tag-legacy/PhoneTag/Classes/`

### When You're Stuck
- Ask Claude Code to explain the architecture
- Request example implementations from the docs
- Use `/help` to see available commands
- Check Firebase and SwiftUI best practices

## Technology Stack

### Core Frameworks
- **SwiftUI**: All UI implementation
- **Swift 6**: Strict concurrency mode (use `@MainActor`, `async/await`, Sendable protocols)
- **MapKit**: Map display and location selection
- **Core Location**: GPS tracking and geofencing
- **Firebase**:
  - Authentication (phone number or Apple Sign-In)
  - Realtime Database (game state, active games, tags)
  - Cloud Functions (game logic validation, tag processing)
  - Cloud Messaging (push notifications)
- **StoreKit 2**: In-app purchases
- **swift-dependencies**: Dependency injection (PointFree library)
- **SwiftData**: Local caching (iOS 17+)

### Architecture Patterns
```swift
// MVVM with Observation
@Observable
class GameViewModel {
    // Use @Observable from Observation framework (iOS 17+)
}

// Repository Pattern
protocol GameRepository {
    func createGame(with players: [String]) async throws -> Game
    func fetchActiveGames() async throws -> [Game]
}

// Dependency Injection
@Dependency(\.gameRepository) var gameRepository
```

## Critical Implementation Rules

### 1. Location Privacy & Battery Life
```swift
// ⚠️ CRITICAL: Request permissions in this order
// 1. Request "When In Use" authorization first
// 2. Only request "Always" when user starts a game
// 3. Use significant location changes, NOT continuous updates
// 4. Use region monitoring for tripwires (geofencing), not polling

// GOOD:
locationManager.requestWhenInUseAuthorization()
locationManager.allowsBackgroundLocationUpdates = false
locationManager.distanceFilter = 100 // meters

// BAD:
locationManager.requestAlwaysAuthorization() // Don't request this first!
locationManager.distanceFilter = kCLDistanceFilterNone // Battery killer!
```

### 2. Game State Management
```swift
// ✅ CORRECT: Firebase is source of truth
// Game state lives in Firebase Realtime Database
// Local state is READ-ONLY cache
// All writes go through Cloud Functions

// ❌ WRONG: Never trust client-side state
// Don't validate tags client-side
// Don't calculate strikes locally
// Don't determine hit/miss without server
```

### 3. Security & Validation
```swift
// ALL game actions MUST be validated server-side via Cloud Functions:
// - validateTag: Calculate actual distance, check safe bases, update strikes
// - createSafeBase: Verify tag actually missed
// - placeTripwire: Verify player is physically at location
// - resetDailyTags: Scheduled function, runs at midnight per timezone

// Firebase Security Rules prevent:
// - Reading other players' exact locations
// - Direct writes to game state (must go through Cloud Functions)
// - Modifying strikes or tag counts directly
```

## Data Models

### Core Models (Place in Models/ directory)

```swift
// Models/User.swift
struct User: Identifiable, Codable, Sendable {
    let id: String // Firebase Auth UID
    let phoneNumber: String
    let displayName: String
    let createdAt: Date
    var friendIds: [String]
    var activeGameIds: [String]
}

// Models/Game.swift
struct Game: Identifiable, Codable, Sendable {
    let id: String
    let createdAt: Date
    var players: [String: PlayerState] // userId: PlayerState
    let createdBy: String
    var status: GameStatus
    var startedAt: Date?
    var endedAt: Date?
}

enum GameStatus: String, Codable, Sendable {
    case waiting    // Waiting for all players to set home bases
    case active     // Game is running
    case completed  // Game has ended
}

// Models/PlayerState.swift
struct PlayerState: Codable, Sendable {
    var strikes: Int                    // 3 at game start
    var tagsRemainingToday: Int         // Resets at midnight
    var homeBase1: CLLocationCoordinate2D?
    var homeBase2: CLLocationCoordinate2D?
    var safeBases: [SafeBase]
    var isActive: Bool                  // false when strikes = 0
    var tripwires: [Tripwire]
    var purchasedTags: PurchasedTags
}

struct PurchasedTags: Codable, Sendable {
    var extraBasicTags: Int
    var wideRadiusTags: Int
}

// Models/Tag.swift
struct Tag: Identifiable, Codable, Sendable {
    let id: String
    let gameId: String
    let fromUserId: String
    let targetUserId: String
    let guessedLocation: GeoPoint
    let timestamp: Date
    var result: TagResult?
    let tagType: TagType
}

enum TagResult: Codable, Sendable {
    case hit(actualLocation: GeoPoint, distance: Double)
    case miss(distance: Double)
    case blocked(reason: BlockReason)
}

enum BlockReason: String, Codable, Sendable {
    case homeBase
    case safeBase
    case outOfTags
    case playerEliminated
}

enum TagType: String, Codable, Sendable {
    case basic          // ~80m radius (~1 block)
    case wideRadius     // ~300m radius (3-5 blocks)
}

// Models/SafeBase.swift
struct SafeBase: Identifiable, Codable, Sendable {
    let id: String
    let location: CLLocationCoordinate2D
    let createdAt: Date
    let type: SafeBaseType
    let expiresAt: Date?  // nil = permanent
}

enum SafeBaseType: String, Codable, Sendable {
    case homeBase       // Set at game start
    case missedTag      // Expires at midnight
    case hitTag         // Permanent for game duration
}

// Models/Tripwire.swift
struct Tripwire: Identifiable, Codable, Sendable {
    let id: String
    let placedBy: String
    let gameId: String
    let path: [CLLocationCoordinate2D]
    let placedAt: Date
    var triggeredBy: String?
    var triggeredAt: Date?
    let isPermanent: Bool
}
```

### Codable Helpers for CLLocationCoordinate2D
```swift
// ⚠️ CLLocationCoordinate2D is not Codable by default
// Add this extension:

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

// Also make it Sendable for Swift 6 concurrency
extension CLLocationCoordinate2D: @unchecked Sendable {}
```

## Game Logic Rules & Constants

### Distance Calculations
```swift
// Utilities/Constants.swift
enum GameConstants {
    // Tag Radii (in meters)
    static let basicTagRadius: CLLocationDistance = 80    // ~1 NYC block
    static let wideRadiusTagRadius: CLLocationDistance = 300  // ~3-5 blocks
    
    // Game Settings
    static let startingStrikes = 3
    static let dailyTagLimit = 5
    static let homeBaseRadius: CLLocationDistance = 50  // meters
    static let safeBaseRadius: CLLocationDistance = 50  // meters
    
    // Location Update Settings
    static let significantLocationChangeDistance: CLLocationDistance = 100
    static let backgroundLocationUpdateInterval: TimeInterval = 300 // 5 minutes
}

// Use CLLocation.distance(from:) for accurate geo calculations
func isWithinTagRadius(_ location: CLLocation, target: CLLocation, tagType: TagType) -> Bool {
    let distance = location.distance(from: target)
    let radius = tagType == .basic ? GameConstants.basicTagRadius : GameConstants.wideRadiusTagRadius
    return distance <= radius
}
```

### Tag Validation Logic (Server-Side)
```javascript
// This goes in Firebase Cloud Functions
// Cloud Functions are written in JavaScript/TypeScript, NOT Swift

// functions/src/index.ts
export const validateTag = functions.https.onCall(async (data, context) => {
    // 1. Verify authenticated
    if (!context.auth) throw new Error('Unauthorized');
    
    // 2. Get game and player states
    const { gameId, targetUserId, guessedLat, guessedLng, tagType } = data;
    const game = await db.ref(`games/${gameId}`).once('value');
    
    // 3. Get target's ACTUAL current location (from recent update)
    const targetLocation = await db.ref(`locations/${targetUserId}/current`).once('value');
    
    // 4. Calculate distance using Haversine formula
    const distance = calculateDistance(
        { lat: guessedLat, lng: guessedLng },
        targetLocation.val()
    );
    
    // 5. Check if within any safe base (including home bases)
    const targetPlayer = game.val().players[targetUserId];
    const inSafeBase = checkSafeBases(targetLocation.val(), targetPlayer);
    
    if (inSafeBase) {
        return { result: 'blocked', reason: 'safeBase' };
    }
    
    // 6. Check if within tag radius
    const radius = tagType === 'basic' ? 80 : 300;
    const isHit = distance <= radius;
    
    if (isHit) {
        // Decrement strikes using transaction to prevent race conditions
        await db.ref(`games/${gameId}/players/${targetUserId}/strikes`)
            .transaction(strikes => Math.max(0, strikes - 1));
        
        // Create permanent safe base at hit location
        await createSafeBase(gameId, targetUserId, targetLocation.val(), 'hitTag');
        
        return { result: 'hit', distance, actualLocation: targetLocation.val() };
    } else {
        // Create temporary safe base at guessed location (expires midnight)
        await createSafeBase(gameId, targetUserId, 
            { lat: guessedLat, lng: guessedLng }, 'missedTag');
        
        return { result: 'miss', distance };
    }
});
```

## Firebase Database Structure

```
/users/{userId}
  displayName: "John Doe"
  phoneNumber: "+15551234567"
  friendIds: ["uid1", "uid2"]
  activeGameIds: ["game1", "game2"]
  createdAt: 1234567890

/games/{gameId}
  createdBy: "uid1"
  createdAt: 1234567890
  status: "active" | "waiting" | "completed"
  startedAt: 1234567890
  endedAt: null
  players:
    {userId}:
      strikes: 3
      tagsRemainingToday: 5
      homeBase1: { latitude: 40.7128, longitude: -74.0060 }
      homeBase2: { latitude: 40.7589, longitude: -73.9851 }
      safeBases:
        - id: "base1"
          location: { latitude: ..., longitude: ... }
          type: "missedTag"
          expiresAt: 1234567890
      isActive: true
      tripwires: [...]
      purchasedTags:
        extraBasicTags: 0
        wideRadiusTags: 5

/tags/{gameId}/{tagId}
  fromUserId: "uid1"
  targetUserId: "uid2"
  guessedLocation: { latitude: ..., longitude: ... }
  timestamp: 1234567890
  result:
    type: "hit" | "miss" | "blocked"
    distance: 45.6
    actualLocation: { latitude: ..., longitude: ... }
  tagType: "basic" | "wideRadius"

/locations/{userId}
  current:
    latitude: 40.7128
    longitude: -74.0060
    timestamp: 1234567890
    accuracy: 10.0
  history:
    - timestamp: 1234567890
      latitude: ...
      longitude: ...

/friendRequests/{userId}/{requestId}
  from: "uid1"
  to: "uid2"
  status: "pending" | "accepted" | "rejected"
  createdAt: 1234567890
```

## Services Layer

### LocationService.swift
```swift
// Services/LocationService.swift
@MainActor
final class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    
    override init() {
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = GameConstants.significantLocationChangeDistance
    }
    
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestAlwaysAuthorization() {
        // Only call this when game starts!
        locationManager.requestAlwaysAuthorization()
    }
    
    func startMonitoring() {
        locationManager.startUpdatingLocation()
    }
    
    func startMonitoringSignificantChanges() {
        // Battery-efficient option
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func addGeofence(for tripwire: Tripwire) {
        // Create CLCircularRegion from tripwire path
        // Monitor for entry
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        // Upload to Firebase every 5 minutes if in active game
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
```

### FirebaseService.swift
```swift
// Services/FirebaseService.swift
import FirebaseDatabase
import FirebaseAuth

actor FirebaseService {
    private let database = Database.database()
    
    func createGame(createdBy: String, playerIds: [String]) async throws -> String {
        let ref = database.reference().child("games").childByAutoId()
        let gameId = ref.key!
        
        var players: [String: [String: Any]] = [:]
        for playerId in playerIds {
            players[playerId] = [
                "strikes": GameConstants.startingStrikes,
                "tagsRemainingToday": GameConstants.dailyTagLimit,
                "isActive": true,
                "safeBases": [],
                "tripwires": [],
                "purchasedTags": ["extraBasicTags": 0, "wideRadiusTags": 0]
            ]
        }
        
        let gameData: [String: Any] = [
            "createdBy": createdBy,
            "createdAt": ServerValue.timestamp(),
            "status": GameStatus.waiting.rawValue,
            "players": players
        ]
        
        try await ref.setValue(gameData)
        return gameId
    }
    
    func observeGame(_ gameId: String) -> AsyncStream<Game> {
        AsyncStream { continuation in
            let ref = database.reference().child("games/\(gameId)")
            let handle = ref.observe(.value) { snapshot in
                guard let game = try? snapshot.data(as: Game.self) else { return }
                continuation.yield(game)
            }
            
            continuation.onTermination = { _ in
                ref.removeObserver(withHandle: handle)
            }
        }
    }
}
```

## UI Implementation

### MapView.swift
```swift
// Views/MapView.swift
import SwiftUI
import MapKit

struct MapView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedLocation: CLLocationCoordinate2D?
    
    let homeBase1: CLLocationCoordinate2D?
    let homeBase2: CLLocationCoordinate2D?
    let safeBases: [SafeBase]
    let tripwires: [Tripwire]
    
    var body: some View {
        Map(position: $cameraPosition) {
            // User location
            UserAnnotation()
            
            // Home bases (green)
            if let homeBase1 {
                Annotation("Home 1", coordinate: homeBase1) {
                    Circle()
                        .fill(.green.opacity(0.3))
                        .stroke(.green, lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
            }
            
            if let homeBase2 {
                Annotation("Home 2", coordinate: homeBase2) {
                    Circle()
                        .fill(.green.opacity(0.3))
                        .stroke(.green, lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
            }
            
            // Safe bases (yellow)
            ForEach(safeBases) { safeBase in
                Annotation("Safe Base", coordinate: safeBase.location) {
                    Circle()
                        .fill(.yellow.opacity(0.3))
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
            }
            
            // Tripwires (red lines)
            ForEach(tripwires) { tripwire in
                MapPolyline(coordinates: tripwire.path)
                    .stroke(.red, lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
}
```

### TagTargetView.swift
```swift
// Views/TagTargetView.swift
struct TagTargetView: View {
    @State private var selectedFriend: User?
    @State private var guessedLocation: CLLocationCoordinate2D?
    @State private var selectedTagType: TagType = .basic
    @State private var isProcessing = false
    @State private var tagResult: TagResult?
    
    let game: Game
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            // Friend selector
            Picker("Select Target", selection: $selectedFriend) {
                ForEach(activePlayers) { player in
                    Text(player.displayName).tag(player as User?)
                }
            }
            
            // Map to drop pin
            MapView(/* ... */)
                .onTapGesture { location in
                    guessedLocation = location
                }
            
            // Tag type selector
            Picker("Tag Type", selection: $selectedTagType) {
                Text("Basic (1 block)").tag(TagType.basic)
                Text("Wide Radius (3-5 blocks)").tag(TagType.wideRadius)
            }
            
            // Submit button
            Button("Submit Tag") {
                Task {
                    await submitTag()
                }
            }
            .disabled(selectedFriend == nil || guessedLocation == nil || isProcessing)
        }
        .alert("Tag Result", isPresented: .constant(tagResult != nil)) {
            Button("OK") {
                tagResult = nil
                onDismiss()
            }
        } message: {
            if let result = tagResult {
                Text(resultMessage(for: result))
            }
        }
    }
    
    private func submitTag() async {
        guard let friend = selectedFriend,
              let location = guessedLocation else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Call Cloud Function
        // This returns the validated result
        let result = await FirebaseService.shared.validateTag(
            gameId: game.id,
            targetUserId: friend.id,
            guessedLocation: location,
            tagType: selectedTagType
        )
        
        tagResult = result
    }
}
```

## StoreKit 2 Implementation

```swift
// Services/StoreService.swift
import StoreKit

enum IAPProduct: String {
    case wideRadiusPack5 = "com.phonetag.wideradius.5"
    case basicTagPack10 = "com.phonetag.basictag.10"
    case tripwirePack3 = "com.phonetag.tripwire.3"
}

@MainActor
final class StoreService: ObservableObject {
    @Published var products: [Product] = []
    private var updates: Task<Void, Never>?
    
    init() {
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await updatePurchases()
                }
            }
        }
    }
    
    deinit {
        updates?.cancel()
    }
    
    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                IAPProduct.wideRadiusPack5.rawValue,
                IAPProduct.basicTagPack10.rawValue,
                IAPProduct.tripwirePack3.rawValue
            ])
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                // Update Firebase with purchase
                await updateFirebaseWithPurchase(transaction)
                await transaction.finish()
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }
    
    private func updateFirebaseWithPurchase(_ transaction: Transaction) async {
        // Validate receipt server-side
        // Update user's purchasedTags in Firebase
    }
}
```

## Push Notifications

```swift
// Services/NotificationService.swift
import UserNotifications
import FirebaseMessaging

enum NotificationType: String {
    case tagged = "tagged"
    case tripwireTriggered = "tripwire_triggered"
    case gameStarted = "game_started"
    case eliminated = "eliminated"
}

@MainActor
final class NotificationService: NSObject, ObservableObject {
    func requestAuthorization() async throws {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        if let type = userInfo["type"] as? String,
           let notificationType = NotificationType(rawValue: type) {
            handleNotification(type: notificationType, userInfo: userInfo)
        }
    }
    
    private func handleNotification(type: NotificationType, userInfo: [AnyHashable: Any]) {
        switch type {
        case .tagged:
            // Navigate to game view
            break
        case .tripwireTriggered:
            // Show tripwire alert
            break
        case .gameStarted:
            // Navigate to game
            break
        case .eliminated:
            // Show elimination screen
            break
        }
    }
}
```

## Development Phases & Milestones

### Phase 1: Foundation (Week 1-2)
**Goal**: Basic app structure and authentication

- [ ] Project setup with Firebase, SwiftUI, Swift 6
- [ ] User authentication (phone number via Firebase Auth)
- [ ] Basic models (User, Game, Tag)
- [ ] Firebase service layer
- [ ] Location service setup (request permissions only)

**Claude Code Tasks**:
```bash
# Start with:
claude -p "Set up the Xcode project with SwiftUI, Firebase, and swift-dependencies. Configure Firebase authentication for phone numbers. Create the basic project structure as outlined in CLAUDE.md."
```

### Phase 2: Core Game Mechanics (Week 3-4)
**Goal**: Game creation, home base setup, basic tagging

- [ ] Friend system (add by phone, friend requests)
- [ ] Create game flow
- [ ] Game lobby (show players, ready status)
- [ ] Home base setup (2 base requirement)
- [ ] Basic map view with annotations
- [ ] Tag submission (UI only, no validation yet)
- [ ] Cloud Function: `validateTag` (server-side logic)
- [ ] Cloud Function: `createSafeBase`

**Claude Code Tasks**:
```bash
# For each feature:
claude -p "Implement the friend system with Firebase. Users should be able to send friend requests by phone number, and accept/reject requests."

claude -p "Create the game lobby view. Show invited players and their ready status (whether they've set home bases). Enable start button only when all players are ready."
```

### Phase 3: Game State & Logic (Week 5)
**Goal**: Complete tag mechanics with strikes and safe bases

- [ ] Strike system (decrement on hit)
- [ ] Safe base creation (on miss and hit)
- [ ] Safe base expiration (midnight reset for missed tags)
- [ ] Daily tag limit and reset
- [ ] Cloud Function: `resetDailyTags` (scheduled)
- [ ] Player elimination (strikes = 0)
- [ ] Game completion detection
- [ ] Real-time game state updates

**Claude Code Tasks**:
```bash
claude -p "Implement the validateTag Cloud Function. It should calculate distance between guess and target's actual location, check safe bases, determine hit/miss/blocked, update strikes, and create safe bases."
```

### Phase 4: Advanced Features (Week 6)
**Goal**: Tripwires and geofencing

- [ ] Tripwire placement UI
- [ ] Tripwire path drawing on map
- [ ] Geofence setup (CLCircularRegion)
- [ ] Location verification (must be at location to place)
- [ ] Cloud Function: `processTripwireCrossing`
- [ ] Tripwire notifications
- [ ] Permanent vs. expire-on-trigger logic

### Phase 5: Monetization (Week 7)
**Goal**: In-app purchases

- [ ] StoreKit 2 integration
- [ ] Product loading and display
- [ ] Purchase flow
- [ ] Receipt validation (server-side)
- [ ] Wide radius tag implementation
- [ ] Extra tag pack implementation
- [ ] Tripwire pack implementation
- [ ] Update Firebase with purchase quantities

### Phase 6: Polish & Testing (Week 8-9)
**Goal**: Production-ready app

- [ ] Animations and transitions
- [ ] Sound effects
- [ ] Onboarding flow for new users
- [ ] Error states and offline handling
- [ ] Comprehensive unit tests
- [ ] UI tests for critical flows
- [ ] Performance optimization
- [ ] Battery usage testing
- [ ] Privacy policy and terms
- [ ] App Store assets (screenshots, description)
- [ ] Beta testing with TestFlight

## Testing Strategy

### Unit Tests
```swift
// Test in isolation using mocked dependencies

class GameLogicTests: XCTestCase {
    func testTagDistanceCalculation() {
        // Test hit/miss based on distance
    }
    
    func testSafeBaseExpiration() {
        // Test that missed tag safe bases expire at midnight
    }
    
    func testStrikeDeduction() {
        // Test strike decrement on successful tag
    }
    
    func testPlayerElimination() {
        // Test isActive = false when strikes = 0
    }
}
```

### Integration Tests
```swift
// Test with real Firebase (using emulator suite)

class FirebaseIntegrationTests: XCTestCase {
    override func setUp() {
        // Configure Firebase emulator
        Database.database().useEmulator(withHost: "localhost", port: 9000)
    }
    
    func testCreateGame() async throws {
        let gameId = try await firebaseService.createGame(
            createdBy: "testUser",
            playerIds: ["user1", "user2"]
        )
        XCTAssertFalse(gameId.isEmpty)
    }
}
```

### UI Tests
```swift
class PhoneTagUITests: XCTestCase {
    func testCompleteTagFlow() {
        // Test full flow: select friend, drop pin, submit tag
    }
    
    func testHomeBaseSetup() {
        // Test setting both home bases
    }
}
```

## Performance & Battery Optimization

### Location Updates
```swift
// ✅ GOOD: Use significant location changes
locationManager.startMonitoringSignificantLocationChanges()

// ✅ GOOD: Set appropriate distance filter
locationManager.distanceFilter = 100 // meters

// ❌ BAD: Continuous high-accuracy updates
locationManager.distanceFilter = kCLDistanceFilterNone // Battery drain!
locationManager.startUpdatingLocation() // Only when necessary!
```

### Firebase Listeners
```swift
// ✅ GOOD: Only observe active game
func observeGame(_ gameId: String) {
    let ref = database.reference().child("games/\(gameId)")
    ref.observe(.value) { snapshot in
        // Update UI
    }
}

// ✅ GOOD: Clean up listeners
deinit {
    database.reference().removeAllObservers()
}

// ❌ BAD: Observing all games
database.reference().child("games").observe(.value) // Too broad!
```

### Caching Strategy
```swift
// Use SwiftData or Core Data to cache:
// - User's active games
// - Friend list
// - Recent game states

// Sync with Firebase:
// - On app launch
// - Every 5 minutes during active game
// - On significant location change
```

## Common Pitfalls & Solutions

### 1. Time Synchronization
```swift
// ❌ WRONG: Using device time
let now = Date()

// ✅ RIGHT: Using server timestamp
let ref = database.reference().child("tags").childByAutoId()
ref.setValue(["timestamp": ServerValue.timestamp()])
```

### 2. Race Conditions
```swift
// ❌ WRONG: Direct strike update
ref.setValue(["strikes": currentStrikes - 1])

// ✅ RIGHT: Using transaction
ref.runTransactionBlock { currentData in
    guard var value = currentData.value as? [String: Any],
          var strikes = value["strikes"] as? Int else {
        return TransactionResult.abort()
    }
    strikes = max(0, strikes - 1)
    value["strikes"] = strikes
    currentData.value = value
    return TransactionResult.success(withValue: currentData)
}
```

### 3. Memory Leaks
```swift
// ❌ WRONG: Strong reference cycle
class ViewModel: ObservableObject {
    var locationService: LocationService!
    
    init() {
        locationService.onUpdate = { [self] location in
            // Strong reference to self!
        }
    }
}

// ✅ RIGHT: Weak reference
locationService.onUpdate = { [weak self] location in
    self?.handleLocation(location)
}
```

### 4. Background Location Updates
```swift
// ⚠️ CRITICAL: Must enable background modes in Xcode
// Signing & Capabilities > Background Modes > Location updates

// ⚠️ CRITICAL: Set background property
locationManager.allowsBackgroundLocationUpdates = true
locationManager.pausesLocationUpdatesAutomatically = false

// ⚠️ CRITICAL: Add required keys to Info.plist
// NSLocationWhenInUseUsageDescription
// NSLocationAlwaysAndWhenInUseUsageDescription
```

## File Structure
```
PhoneTag/
├── PhoneTagApp.swift                    # @main entry point
├── Models/
│   ├── User.swift
│   ├── Game.swift
│   ├── PlayerState.swift
│   ├── Tag.swift
│   ├── SafeBase.swift
│   ├── Tripwire.swift
│   └── Extensions/
│       └── CLLocationCoordinate2D+Codable.swift
├── ViewModels/
│   ├── GameViewModel.swift              # @Observable
│   ├── MapViewModel.swift
│   ├── TagViewModel.swift
│   └── StoreViewModel.swift
├── Views/
│   ├── MapView.swift
│   ├── GameLobbyView.swift
│   ├── ActiveGamesView.swift
│   ├── TagTargetView.swift
│   ├── HomeBaseSetupView.swift
│   ├── StoreView.swift
│   └── Components/
│       ├── PlayerCard.swift
│       ├── SafeBaseAnnotation.swift
│       └── TripwireOverlay.swift
├── Services/
│   ├── LocationService.swift            # @MainActor
│   ├── FirebaseService.swift            # actor
│   ├── NotificationService.swift        # @MainActor
│   └── StoreService.swift               # @MainActor
├── Repositories/
│   ├── GameRepository.swift
│   ├── UserRepository.swift
│   └── TagRepository.swift
├── Utilities/
│   ├── Constants.swift
│   ├── Extensions/
│   │   ├── Date+Extensions.swift
│   │   └── CLLocation+Extensions.swift
│   └── Helpers/
│       ├── DistanceCalculator.swift
│       └── GeofenceManager.swift
└── Resources/
    ├── Assets.xcassets
    ├── Sounds/
    └── Info.plist

functions/                                # Firebase Cloud Functions
├── src/
│   ├── index.ts
│   ├── validateTag.ts
│   ├── resetDailyTags.ts
│   └── processTripwireCrossing.ts
└── package.json
```

## Swift 6 Concurrency Checklist

- [ ] Enable strict concurrency in build settings
- [ ] Mark all model structs as `Sendable`
- [ ] Use `@MainActor` for UI-related classes
- [ ] Use `actor` for shared mutable state
- [ ] Prefer `async/await` over completion handlers
- [ ] Use `@unchecked Sendable` sparingly (only for CLLocationCoordinate2D)
- [ ] Avoid `@MainActor` on value types

## Code Quality Standards

```swift
// ✅ Good practices:
// 1. Use descriptive variable names
let homeBaseRadius = GameConstants.homeBaseRadius
let isWithinHomeBase = distance <= homeBaseRadius

// 2. Extract magic numbers to constants
enum GameConstants {
    static let basicTagRadius: CLLocationDistance = 80
}

// 3. Add documentation
/// Calculates whether a tag hits its target
/// - Parameters:
///   - guess: The location guessed by the tagger
///   - actual: The actual location of the target
///   - tagType: The type of tag used
/// - Returns: True if the tag is within radius
func isTagHit(guess: CLLocation, actual: CLLocation, tagType: TagType) -> Bool

// 4. Use enums for string literals
enum FirebasePath {
    static let games = "games"
    static let users = "users"
    static let tags = "tags"
}

// 5. Handle errors gracefully
do {
    let game = try await createGame(players: players)
} catch {
    showError("Failed to create game: \(error.localizedDescription)")
}
```

## Working with Claude Code: Best Practices

1. **Start with Plan Mode** for complex features
   ```bash
   claude --permission-mode plan
   > I need to implement the tag validation system. Analyze the requirements and create a detailed plan.
   ```

2. **Be specific in your requests**
   ```bash
   # ❌ Vague
   > Make the map view
   
   # ✅ Specific
   > Create MapView.swift that displays user location, home bases as green circles, safe bases as yellow circles with expiry timers, and tripwires as red polylines. Use the new MapKit API with Map and annotations.
   ```

3. **Request tests alongside features**
   ```bash
   > Implement the validateTag Cloud Function and write comprehensive tests that cover hit scenarios, miss scenarios, safe base blocking, and edge cases.
   ```

4. **Ask for explanations**
   ```bash
   > Explain how the geofencing system works for tripwires and why we use CLCircularRegion instead of continuous location monitoring.
   ```

5. **Iterate on generated code**
   ```bash
   > The LocationService is too coupled to Firebase. Refactor to use the repository pattern with protocol-based dependency injection.
   ```

## Questions to Ask Yourself

- **Architecture**: Does this feature belong in a ViewModel, Service, or Repository?
- **Performance**: Will this drain battery? Can I use geofencing instead of polling?
- **Security**: Is this validated server-side? Can a user cheat?
- **Privacy**: Am I exposing exact locations when I shouldn't?
- **Testing**: Can I write a unit test for this logic?
- **Concurrency**: Am I using the right isolation (actor, @MainActor, etc.)?

## When You're Stuck

1. Read the relevant section in this CLAUDE.md
2. Ask Claude Code to explain the architecture
3. Request example implementations
4. Check Firebase and SwiftUI documentation
5. Ask for alternative approaches

## Legacy Codebase Reference

### Location
The 2012 original codebase is at: `../phone-tag-legacy/`

### Before Implementing Any UI
```bash
# Example workflow for implementing a new screen:
> Read ../phone-tag-legacy/PhoneTag/Classes/MapViewController.m and analyze:
> - Layout structure and UI hierarchy  
> - Button placement and actions
> - Visual styling (colors, fonts, spacing)
> - Navigation patterns
> - User interaction flow
> Then create a modern SwiftUI equivalent in Views/MapView.swift that matches the original UX.
```

### Legacy → Modern Translation Guide

#### Common Objective-C/UIKit → Swift/SwiftUI Conversions

**View Controllers → Views**
```objective-c
// Legacy: UIViewController
@interface MapViewController : UIViewController
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UIButton *tagButton;
@end
```
```swift
// Modern: SwiftUI View
struct MapView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        Map(position: $cameraPosition) {
            // Annotations
        }
        .overlay(alignment: .bottom) {
            Button("Tag") { /* ... */ }
        }
    }
}
```

**Map Views**
```objective-c
// Legacy: MKMapView with delegates
MKMapView *mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
mapView.delegate = self;
[self.view addSubview:mapView];

// Add annotation
MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
annotation.coordinate = CLLocationCoordinate2DMake(40.7128, -74.0060);
[mapView addAnnotation:annotation];
```
```swift
// Modern: SwiftUI Map
Map(position: $cameraPosition) {
    Annotation("Home Base", coordinate: homeBase) {
        Circle()
            .fill(.green.opacity(0.3))
            .frame(width: 40, height: 40)
    }
}
```

**Table Views → Lists**
```objective-c
// Legacy: UITableView with datasource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.friends.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FriendCell"];
    Friend *friend = self.friends[indexPath.row];
    cell.textLabel.text = friend.name;
    return cell;
}
```
```swift
// Modern: SwiftUI List
List(friends) { friend in
    Text(friend.name)
}
```

**Navigation**
```objective-c
// Legacy: UINavigationController push/pop
MapViewController *mapVC = [[MapViewController alloc] init];
[self.navigationController pushViewController:mapVC animated:YES];

// Modal presentation
TagViewController *tagVC = [[TagViewController alloc] init];
[self presentViewController:tagVC animated:YES completion:nil];
```
```swift
// Modern: SwiftUI NavigationStack
NavigationStack {
    List {
        NavigationLink("Map", value: Route.map)
    }
    .navigationDestination(for: Route.self) { route in
        switch route {
        case .map: MapView()
        }
    }
}

// Modal presentation
.sheet(isPresented: $showingTag) {
    TagTargetView()
}
```

**Alerts**
```objective-c
// Legacy: UIAlertView
UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Tag Result"
                                                message:@"Hit! -1 strike"
                                               delegate:nil
                                      cancelButtonTitle:@"OK"
                                      otherButtonTitles:nil];
[alert show];
```
```swift
// Modern: SwiftUI alert modifier
.alert("Tag Result", isPresented: $showingAlert) {
    Button("OK") { }
} message: {
    Text("Hit! -1 strike")
}
```

**Location Manager**
```objective-c
// Legacy: CLLocationManager with delegates
@interface MapViewController : UIViewController <CLLocationManagerDelegate>
@property (strong, nonatomic) CLLocationManager *locationManager;

- (void)viewDidLoad {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager 
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    // Use location
}
```
```swift
// Modern: SwiftUI with ObservableObject
@MainActor
class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, 
                        didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
```

**Network/Data**
```objective-c
// Legacy: NSURLConnection/AFNetworking
NSURLRequest *request = [NSURLRequest requestWithURL:url];
[NSURLConnection sendAsynchronousRequest:request 
                                   queue:[NSOperationQueue mainQueue]
                       completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
    if (error) {
        // Handle error
    } else {
        // Parse data
    }
}];
```
```swift
// Modern: async/await with URLSession
func fetchData() async throws -> Data {
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
}

// Or with Firebase
actor FirebaseService {
    func fetchGame(_ id: String) async throws -> Game {
        let snapshot = try await database.reference()
            .child("games/\(id)")
            .getData()
        return try snapshot.data(as: Game.self)
    }
}
```

### Visual Design Preservation

When analyzing legacy UI, document:

1. **Colors**: Note hex values or named colors used
2. **Spacing**: Measure padding, margins, button heights
3. **Typography**: Font sizes, weights, styles
4. **Layout**: Constraint relationships, stack arrangements
5. **Icons**: Which SF Symbols to use as modern equivalents
6. **Animations**: Timing, easing, transition styles

**Example Documentation Format**:
```swift
// LEGACY REFERENCE: TagViewController.m
// - Primary button: 44pt height, 16pt corner radius, blue background (#007AFF)
// - Button positioned 20pt from bottom safe area
// - Friend list uses grouped table style with disclosure indicators
// - Tag confirmation shows modal alert with 2 buttons

struct TagTargetView: View {
    // Modern SwiftUI implementation matching above specs
}
```

### Deprecated API Modernization

If the legacy code uses deprecated iOS 6 APIs, replace with modern equivalents:

| Legacy API | Modern Equivalent |
|------------|------------------|
| `UIAlertView` | `.alert()` modifier |
| `UIActionSheet` | `.confirmationDialog()` |
| `UITableViewController` | `List` in SwiftUI |
| `NSUserDefaults` | `@AppStorage` or SwiftData |
| `NSNotificationCenter` | Combine or Observation |
| `performSelectorOnMainThread` | `@MainActor` |
| `dispatch_async(dispatch_get_main_queue())` | `await MainActor.run` |
| MKMapView delegates | New MapKit with SwiftUI |

### Asset Migration

Extract assets from legacy app:
```bash
# Copy image assets from legacy app
> Analyze ../phone-tag-legacy/PhoneTag/Images.xcassets/ and identify all 
> icons and images used. For each:
> - If it's a system icon → Use SF Symbols equivalent
> - If it's custom → Copy to new Assets.xcassets with @2x and @3x versions
> - Document the mapping in ASSET_MIGRATION.md
```

## Final Reminders

- **Server-side validation is non-negotiable** - never trust the client
- **Battery life matters** - use significant location changes
- **Privacy is paramount** - only reveal locations on successful tags
- **Test with real devices** - especially for location features
- **Document complex logic** - future you will thank present you

This guide is your single source of truth. When in doubt, refer back to it.

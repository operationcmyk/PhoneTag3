I'm building Phone Tag, a real-time location-based multiplayer iOS game.

**Context**: You've already analyzed the legacy 2012 codebase and created these reference documents:
- LEGACY_ANALYSIS.md (comprehensive UI/UX analysis)
- UI_REFERENCE.md (visual mockups and screen flows)
- API_MIGRATION.md (legacy PHP → Firebase mapping)
- IMPLEMENTATION_SUMMARY.md (phased roadmap)
- CODE_SNIPPETS.md (ready-to-use code)

**Read CLAUDE.md** for the complete technical specification.

**Your task**: Set up the initial Xcode project with modern iOS architecture:

## 1. Create Xcode Project

- **App Type**: iOS App using SwiftUI
- **Minimum Deployment**: iOS 17.0
- **Swift Version**: Swift 6 with strict concurrency mode enabled
- **App Name**: "Phone Tag"
- **Bundle Identifier**: com.phonetag.app
- **Organization**: Phone Tag Inc

**Build Settings to Configure**:
```
SWIFT_STRICT_CONCURRENCY = complete
ENABLE_STRICT_SWIFT_CHECKING = YES
```

## 2. Install Dependencies via Swift Package Manager

Add these packages:

**Firebase** (https://github.com/firebase/firebase-ios-sdk):
- FirebaseAuth
- FirebaseDatabase
- FirebaseMessaging
- FirebaseAnalytics

**swift-dependencies** (https://github.com/pointfreeco/swift-dependencies):
- Dependencies

**After adding packages**, create a `GoogleService-Info.plist` placeholder with instructions on how to obtain it from Firebase Console.

## 3. Project Structure

Create this exact folder structure inside the PhoneTag/ directory:

```
PhoneTag/
├── PhoneTagApp.swift
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
│   └── (placeholder - will add later)
├── Views/
│   ├── ContentView.swift
│   └── Components/
│       └── (placeholder - will add later)
├── Services/
│   └── (placeholder - will add later)
├── Repositories/
│   └── (placeholder - will add later)
├── Utilities/
│   ├── Constants.swift
│   └── Extensions/
│       └── (placeholder - will add later)
└── Resources/
    └── Assets.xcassets
```

## 4. Implement Core Models

**CRITICAL**: All models must conform to `Codable` and `Sendable` for Swift 6 concurrency.

### Models/User.swift
```swift
import Foundation

struct User: Identifiable, Codable, Sendable {
    let id: String // Firebase Auth UID
    let phoneNumber: String
    let displayName: String
    let createdAt: Date
    var friendIds: [String]
    var activeGameIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber
        case displayName
        case createdAt
        case friendIds
        case activeGameIds
    }
}
```

### Models/Game.swift
```swift
import Foundation

struct Game: Identifiable, Codable, Sendable {
    let id: String
    let createdAt: Date
    var players: [String: PlayerState] // userId: PlayerState
    let createdBy: String
    var status: GameStatus
    var startedAt: Date?
    var endedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case players
        case createdBy
        case status
        case startedAt
        case endedAt
    }
}

enum GameStatus: String, Codable, Sendable {
    case waiting    // Waiting for all players to set home bases
    case active     // Game is running
    case completed  // Game has ended
}
```

### Models/PlayerState.swift
```swift
import Foundation
import CoreLocation

struct PlayerState: Codable, Sendable {
    var strikes: Int                        // 3 at game start
    var tagsRemainingToday: Int             // Resets at midnight
    var homeBase1: CLLocationCoordinate2D?
    var homeBase2: CLLocationCoordinate2D?
    var safeBases: [SafeBase]
    var isActive: Bool                      // false when strikes = 0
    var tripwires: [Tripwire]
    var purchasedTags: PurchasedTags
    
    enum CodingKeys: String, CodingKey {
        case strikes
        case tagsRemainingToday
        case homeBase1
        case homeBase2
        case safeBases
        case isActive
        case tripwires
        case purchasedTags
    }
}

struct PurchasedTags: Codable, Sendable {
    var extraBasicTags: Int
    var wideRadiusTags: Int
    
    enum CodingKeys: String, CodingKey {
        case extraBasicTags
        case wideRadiusTags
    }
}
```

### Models/Tag.swift
```swift
import Foundation
import FirebaseDatabase

struct Tag: Identifiable, Codable, Sendable {
    let id: String
    let gameId: String
    let fromUserId: String
    let targetUserId: String
    let guessedLocation: GeoPoint
    let timestamp: Date
    var result: TagResult?
    let tagType: TagType
    
    enum CodingKeys: String, CodingKey {
        case id
        case gameId
        case fromUserId
        case targetUserId
        case guessedLocation
        case timestamp
        case result
        case tagType
    }
}

enum TagResult: Codable, Sendable {
    case hit(actualLocation: GeoPoint, distance: Double)
    case miss(distance: Double)
    case blocked(reason: BlockReason)
    
    enum CodingKeys: String, CodingKey {
        case type
        case actualLocation
        case distance
        case reason
    }
    
    enum ResultType: String, Codable {
        case hit, miss, blocked
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hit(let location, let distance):
            try container.encode(ResultType.hit, forKey: .type)
            try container.encode(location, forKey: .actualLocation)
            try container.encode(distance, forKey: .distance)
        case .miss(let distance):
            try container.encode(ResultType.miss, forKey: .type)
            try container.encode(distance, forKey: .distance)
        case .blocked(let reason):
            try container.encode(ResultType.blocked, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResultType.self, forKey: .type)
        switch type {
        case .hit:
            let location = try container.decode(GeoPoint.self, forKey: .actualLocation)
            let distance = try container.decode(Double.self, forKey: .distance)
            self = .hit(actualLocation: location, distance: distance)
        case .miss:
            let distance = try container.decode(Double.self, forKey: .distance)
            self = .miss(distance: distance)
        case .blocked:
            let reason = try container.decode(BlockReason.self, forKey: .reason)
            self = .blocked(reason: reason)
        }
    }
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

// GeoPoint wrapper for Firebase compatibility
struct GeoPoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}
```

### Models/SafeBase.swift
```swift
import Foundation
import CoreLocation

struct SafeBase: Identifiable, Codable, Sendable {
    let id: String
    let location: CLLocationCoordinate2D
    let createdAt: Date
    let type: SafeBaseType
    let expiresAt: Date?  // nil = permanent
    
    enum CodingKeys: String, CodingKey {
        case id
        case location
        case createdAt
        case type
        case expiresAt
    }
}

enum SafeBaseType: String, Codable, Sendable {
    case homeBase       // Set at game start
    case missedTag      // Expires at midnight
    case hitTag         // Permanent for game duration
}
```

### Models/Tripwire.swift
```swift
import Foundation
import CoreLocation

struct Tripwire: Identifiable, Codable, Sendable {
    let id: String
    let placedBy: String
    let gameId: String
    let path: [CLLocationCoordinate2D]
    let placedAt: Date
    var triggeredBy: String?
    var triggeredAt: Date?
    let isPermanent: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case placedBy
        case gameId
        case path
        case placedAt
        case triggeredBy
        case triggeredAt
        case isPermanent
    }
}
```

### Models/Extensions/CLLocationCoordinate2D+Codable.swift
```swift
import CoreLocation

// CLLocationCoordinate2D is not Codable by default
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

// Make it Sendable for Swift 6 concurrency
extension CLLocationCoordinate2D: @unchecked Sendable {}
```

## 5. Create Constants File

### Utilities/Constants.swift
```swift
import Foundation
import CoreLocation

enum GameConstants {
    // Tag Radii (in meters)
    static let basicTagRadius: CLLocationDistance = 80       // ~1 NYC block
    static let wideRadiusTagRadius: CLLocationDistance = 300 // ~3-5 blocks
    
    // Game Settings
    static let startingStrikes = 3
    static let dailyTagLimit = 5
    static let homeBaseRadius: CLLocationDistance = 50       // meters
    static let safeBaseRadius: CLLocationDistance = 50       // meters
    
    // Location Update Settings
    static let significantLocationChangeDistance: CLLocationDistance = 100
    static let backgroundLocationUpdateInterval: TimeInterval = 300 // 5 minutes
    
    // Firebase Paths
    enum FirebasePath {
        static let users = "users"
        static let games = "games"
        static let tags = "tags"
        static let locations = "locations"
        static let friendRequests = "friendRequests"
    }
}
```

## 6. Configure Info.plist

Add these required keys:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Phone Tag needs your location to show you on the map and enable tagging nearby players.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Phone Tag needs background location access to notify you when tagged and track tripwire crossings during active games.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>remote-notification</string>
</array>
```

## 7. Set Up App Entry Point

### PhoneTagApp.swift
```swift
import SwiftUI
import FirebaseCore

@main
struct PhoneTagApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Views/ContentView.swift
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "location.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Phone Tag")
                .font(.largeTitle)
            Text("Setting up project...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
```

## 8. Create Firebase Setup Instructions

Create a file called `FIREBASE_SETUP.md` with these instructions:

```markdown
# Firebase Setup Instructions

## 1. Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click "Add project"
3. Name it "Phone Tag"
4. Disable Google Analytics (optional)
5. Create project

## 2. Add iOS App

1. Click iOS icon
2. Bundle ID: com.phonetag.app
3. App nickname: Phone Tag
4. Download GoogleService-Info.plist
5. Add it to Xcode project root (next to Info.plist)

## 3. Enable Authentication

1. Go to Authentication → Sign-in method
2. Enable "Phone" authentication
3. Configure reCAPTCHA (follow Firebase instructions)

## 4. Set Up Realtime Database

1. Go to Realtime Database → Create Database
2. Start in test mode (we'll add security rules later)
3. Choose your region (us-central1 recommended)

## 5. Enable Cloud Messaging

1. Go to Cloud Messaging
2. Upload APNs certificate or key (from Apple Developer)
3. Enable push notifications

## Next Steps

After completing this setup:
- Replace the placeholder GoogleService-Info.plist
- Run the app to verify Firebase connection
- Move on to Phase 2: Authentication implementation
```

## Requirements & Constraints

✅ **DO**:
- Use Swift 6 strict concurrency
- Make all models `Sendable`
- Use `async/await` patterns
- Add comprehensive doc comments
- Follow the file structure exactly
- Use `@MainActor` for UI-related code
- Use `actor` for thread-safe services

❌ **DON'T**:
- Implement UI views yet (just placeholders)
- Implement ViewModels yet
- Implement Services yet
- Implement Repositories yet
- Add StoreKit yet
- Implement Firebase Cloud Functions yet

## Deliverables

After completion, show me:

1. **Project structure tree** - Verify all folders/files were created
2. **Build status** - Does it compile with Swift 6 strict concurrency?
3. **Package dependencies** - List installed SPM packages
4. **Key decisions** - Any architecture choices you made
5. **Next steps** - What should we implement in Phase 2?

Ready to proceed? Let me know if you have questions about the architecture or Swift 6 concurrency requirements.

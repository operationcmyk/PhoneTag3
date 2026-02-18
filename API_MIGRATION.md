# Legacy API to Firebase Migration Guide

## Overview
This document maps the legacy PHP API endpoints to modern Firebase Realtime Database structure and Cloud Functions. Use this as a reference when implementing server-side logic.

---

## Legacy API Structure

### Base URL
```
http://www.operationcmyk.com/phonetag/phoneTag.php
```

### Request Format
```
GET: ?fn=[functionName]&param1=value1&param2=value2

POST:
URL: ?fn=[functionName]
Body: param1=value1&param2=value2
Content-Type: application/x-www-form-urlencoded
```

---

## API Endpoint Mapping

### 1. User Arsenal (Inventory)

**Legacy**:
```
GET /phoneTag.php?fn=getuserarsenal&user={userId}

Response:
[
  {
    "id": "123",
    "itemId": "1",
    "itemName": "Basic Bomb",
    "quantity": "5",
    "type": "bomb"
  },
  {
    "id": "124",
    "itemId": "2",
    "itemName": "Wide Radius",
    "quantity": "2",
    "type": "bomb"
  }
]
```

**Modern Firebase**:
```javascript
// Database path: /users/{userId}/arsenal
{
  "basicBombs": 5,
  "wideRadiusBombs": 2,
  "tripwires": 1,
  "extraBases": 0
}

// No Cloud Function needed - direct read
const arsenalRef = database.ref(`users/${userId}/arsenal`);
const snapshot = await arsenalRef.once('value');
const arsenal = snapshot.val();
```

**Swift Code**:
```swift
struct Arsenal: Codable {
    var basicBombs: Int = 0
    var wideRadiusBombs: Int = 0
    var tripwires: Int = 0
    var extraBases: Int = 0
}

func fetchArsenal(userId: String) async throws -> Arsenal {
    let ref = Database.database().reference().child("users/\(userId)/arsenal")
    let snapshot = try await ref.getData()
    return try snapshot.data(as: Arsenal.self)
}
```

---

### 2. Arsenal Store

**Legacy**:
```
GET /phoneTag.php?fn=getarsenalstore

Response:
[
  {
    "id": "1",
    "name": "Basic Bomb Pack x10",
    "price": "0.99",
    "productId": "com.phonetag.basic10",
    "itemType": "bomb",
    "quantity": "10",
    "description": "Standard range bomb"
  },
  {
    "id": "2",
    "name": "Wide Radius Pack x5",
    "price": "1.99",
    "productId": "com.phonetag.wide5",
    "itemType": "bomb",
    "quantity": "5",
    "description": "Large blast radius"
  }
]
```

**Modern Firebase**:
```javascript
// Database path: /storeItems (read-only, admin-managed)
{
  "basicBomb10": {
    "name": "Basic Bomb Pack x10",
    "price": 0.99,
    "productId": "com.phonetag.basic10",
    "type": "basicBomb",
    "quantity": 10,
    "description": "Standard range bomb",
    "sortOrder": 1
  },
  "wideRadius5": {
    "name": "Wide Radius Pack x5",
    "price": 1.99,
    "productId": "com.phonetag.wide5",
    "type": "wideRadiusBomb",
    "quantity": 5,
    "description": "Large blast radius",
    "sortOrder": 2
  }
}

// Cloud Function: validatePurchase
exports.validatePurchase = functions.https.onCall(async (data, context) => {
  // Verify Apple receipt with App Store API
  // Update user's arsenal
  // Return updated arsenal
});
```

**Swift Code with StoreKit 2**:
```swift
@MainActor
class StoreService: ObservableObject {
    @Published var products: [Product] = []

    func loadProducts() async {
        // Load from StoreKit, not Firebase
        products = try await Product.products(for: [
            "com.phonetag.basic10",
            "com.phonetag.wide5"
        ])
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                // Call Firebase to validate and credit
                await validatePurchaseWithFirebase(transaction)
                await transaction.finish()
            }
        default:
            break
        }
    }
}
```

---

### 3. Mine/Tripwire Data

**Legacy**:
```
POST /phoneTag.php?fn=getMineData
Body: uid={userId}

Response:
[
  {
    "id": "456",
    "userWhoDroppedTheMine": "789",
    "mineLat": "40.7128",
    "mineLongi": "-74.0060",
    "radius": "5",  // multiplied by 100 for meters
    "gameId": "game123"
  }
]
```

**Modern Firebase**:
```javascript
// Database path: /games/{gameId}/tripwires
{
  "tripwire_abc": {
    "id": "tripwire_abc",
    "placedBy": "user789",
    "location": {
      "latitude": 40.7128,
      "longitude": -74.0060
    },
    "radius": 500,  // in meters
    "placedAt": 1234567890,
    "triggeredBy": null,
    "triggeredAt": null,
    "isPermanent": true
  }
}

// Cloud Function: placeTripwire
exports.placeTripwire = functions.https.onCall(async (data, context) => {
  const { gameId, location } = data;
  const userId = context.auth.uid;

  // Verify user has tripwires available
  const arsenalRef = db.ref(`users/${userId}/arsenal/tripwires`);
  const currentCount = (await arsenalRef.once('value')).val() || 0;

  if (currentCount <= 0) {
    throw new functions.https.HttpsError('failed-precondition', 'No tripwires available');
  }

  // Create tripwire
  const tripwireRef = db.ref(`games/${gameId}/tripwires`).push();
  await tripwireRef.set({
    id: tripwireRef.key,
    placedBy: userId,
    location: location,
    radius: 500,
    placedAt: admin.database.ServerValue.TIMESTAMP,
    triggeredBy: null,
    isPermanent: true
  });

  // Decrement arsenal
  await arsenalRef.transaction(count => Math.max(0, count - 1));

  return { tripwireId: tripwireRef.key };
});
```

**Swift Code**:
```swift
func placeTripwire(gameId: String, location: CLLocationCoordinate2D) async throws {
    let functions = Functions.functions()
    let callable = functions.httpsCallable("placeTripwire")

    let data: [String: Any] = [
        "gameId": gameId,
        "location": [
            "latitude": location.latitude,
            "longitude": location.longitude
        ]
    ]

    let result = try await callable.call(data)
    guard let tripwireId = result.data as? String else {
        throw GameError.invalidResponse
    }

    // Set up geofencing for this tripwire
    setupGeofence(tripwireId: tripwireId, location: location, radius: 500)
}
```

---

### 4. Update Location

**Legacy**:
```
POST /phoneTag.php?fn=updateLocation
Body: id={userId}&lat={latitude}&longi={longitude}&v={version}

Response: (version check response)
"2.0.1" or "OK"
```

**Modern Firebase**:
```javascript
// Database path: /locations/{userId}
{
  "current": {
    "latitude": 40.7128,
    "longitude": -74.0060,
    "accuracy": 10.0,
    "timestamp": 1234567890
  },
  "history": [
    {
      "latitude": 40.7100,
      "longitude": -74.0050,
      "timestamp": 1234567800
    }
  ]
}

// Security Rules:
{
  "rules": {
    "locations": {
      "$userId": {
        ".write": "$userId === auth.uid",
        ".read": "$userId === auth.uid",
        "current": {
          ".validate": "newData.hasChildren(['latitude', 'longitude', 'timestamp'])"
        }
      }
    }
  }
}

// No Cloud Function needed for simple updates
// Client writes directly with security rules
```

**Swift Code**:
```swift
func updateLocation(_ location: CLLocation) async throws {
    guard let userId = Auth.auth().currentUser?.uid else { return }

    let ref = Database.database().reference()
        .child("locations/\(userId)/current")

    let locationData: [String: Any] = [
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
        "accuracy": location.horizontalAccuracy,
        "timestamp": ServerValue.timestamp()
    ]

    try await ref.setValue(locationData)
}
```

---

### 5. Hit Mine/Tripwire

**Legacy**:
```
POST /phoneTag.php?fn=hitMine
Body: uid={userId}&bombid={mineId}

Response: (success/failure)
```

**Modern Firebase**:
```javascript
// Cloud Function: processTripwireCrossing
exports.processTripwireCrossing = functions.https.onCall(async (data, context) => {
  const { gameId, tripwireId } = data;
  const userId = context.auth.uid;

  // Get tripwire details
  const tripwireRef = db.ref(`games/${gameId}/tripwires/${tripwireId}`);
  const tripwire = (await tripwireRef.once('value')).val();

  // Verify not already triggered
  if (tripwire.triggeredBy) {
    return { alreadyTriggered: true };
  }

  // Mark as triggered
  await tripwireRef.update({
    triggeredBy: userId,
    triggeredAt: admin.database.ServerValue.TIMESTAMP
  });

  // Get user who placed tripwire
  const placedBy = tripwire.placedBy;

  // Send notification to placer
  await sendNotification(placedBy, {
    title: 'Tripwire Triggered!',
    body: 'Someone crossed your tripwire',
    type: 'tripwire_triggered',
    gameId: gameId,
    triggeredBy: userId
  });

  // Get target's current location for placer to see
  const targetLocationRef = db.ref(`locations/${userId}/current`);
  const targetLocation = (await targetLocationRef.once('value')).val();

  return {
    success: true,
    targetLocation: targetLocation
  };
});
```

**Swift Code**:
```swift
// Called when CLLocationManager detects region entry
func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard let tripwireId = region.identifier else { return }

    Task {
        do {
            let functions = Functions.functions()
            let callable = functions.httpsCallable("processTripwireCrossing")

            let data: [String: Any] = [
                "gameId": currentGameId,
                "tripwireId": tripwireId
            ]

            let result = try await callable.call(data)
            // Show notification to user
        } catch {
            print("Error processing tripwire: \(error)")
        }
    }
}
```

---

### 6. Drop Bomb/Tag

**Legacy**:
```
POST /phoneTag.php?fn=dropBomb
Body: uid={userId}&gameid={gameId}&lat={latitude}&longi={longitude}&type={bombType}

Response:
{
  "bombId": "bomb123",
  "hits": [
    {
      "userId": "target456",
      "distance": "45.6",
      "hit": true,
      "newLives": "2"
    }
  ]
}
```

**Modern Firebase**:
```javascript
// Cloud Function: validateTag
exports.validateTag = functions.https.onCall(async (data, context) => {
  const { gameId, guessedLocation, tagType } = data;
  const userId = context.auth.uid;

  // Get game state
  const gameRef = db.ref(`games/${gameId}`);
  const game = (await gameRef.once('value')).val();

  // Verify user has tags remaining
  const playerState = game.players[userId];
  if (playerState.tagsRemainingToday <= 0) {
    throw new functions.https.HttpsError('failed-precondition', 'No tags remaining');
  }

  // Get all active players' locations
  const results = [];

  for (const [targetId, targetState] of Object.entries(game.players)) {
    if (targetId === userId || !targetState.isActive) continue;

    // Get target's actual location
    const targetLocationRef = db.ref(`locations/${targetId}/current`);
    const targetLocation = (await targetLocationRef.once('value')).val();

    if (!targetLocation) continue;

    // Calculate distance using Haversine formula
    const distance = calculateDistance(
      guessedLocation.latitude,
      guessedLocation.longitude,
      targetLocation.latitude,
      targetLocation.longitude
    );

    // Determine hit based on tag type and radius
    const radius = tagType === 'basic' ? 80 : 300; // meters
    const isHit = distance <= radius;

    // Check if target is in safe base
    const inSafeBase = checkSafeBases(targetLocation, targetState);

    let result;
    if (inSafeBase) {
      result = { type: 'blocked', reason: 'safeBase' };
    } else if (isHit) {
      // Decrement strikes
      const newStrikes = Math.max(0, targetState.strikes - 1);
      await gameRef.child(`players/${targetId}/strikes`).set(newStrikes);

      if (newStrikes === 0) {
        await gameRef.child(`players/${targetId}/isActive`).set(false);
      }

      // Create permanent safe base at hit location
      await createSafeBase(gameId, targetId, targetLocation, 'hitTag');

      result = {
        type: 'hit',
        distance: distance,
        actualLocation: targetLocation,
        newStrikes: newStrikes
      };

      // Send notification to target
      await sendNotification(targetId, {
        title: 'You were tagged!',
        body: `You lost 1 life. ${newStrikes} remaining.`,
        type: 'tagged'
      });
    } else {
      // Create temporary safe base at guessed location (expires midnight)
      await createSafeBase(gameId, targetId, guessedLocation, 'missedTag');

      result = {
        type: 'miss',
        distance: distance
      };
    }

    results.push({
      targetId: targetId,
      result: result
    });
  }

  // Decrement tags remaining
  await gameRef.child(`players/${userId}/tagsRemainingToday`).transaction(
    count => Math.max(0, count - 1)
  );

  // Record tag in history
  const tagRef = db.ref(`tags/${gameId}`).push();
  await tagRef.set({
    id: tagRef.key,
    fromUserId: userId,
    guessedLocation: guessedLocation,
    tagType: tagType,
    timestamp: admin.database.ServerValue.TIMESTAMP,
    results: results
  });

  return { results: results };
});

// Helper: Calculate distance using Haversine formula
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371e3; // Earth radius in meters
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;

  const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ/2) * Math.sin(Δλ/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

  return R * c; // in meters
}

// Helper: Check if location is in any safe base
function checkSafeBases(location, playerState) {
  const bases = [
    playerState.homeBase1,
    playerState.homeBase2,
    ...playerState.safeBases.map(b => b.location)
  ];

  for (const base of bases) {
    if (!base) continue;

    const distance = calculateDistance(
      location.latitude,
      location.longitude,
      base.latitude,
      base.longitude
    );

    if (distance <= 50) { // 50m safe base radius
      return true;
    }
  }

  return false;
}

// Helper: Create safe base
async function createSafeBase(gameId, userId, location, type) {
  const safeBaseRef = db.ref(`games/${gameId}/players/${userId}/safeBases`).push();

  const expiresAt = type === 'missedTag'
    ? getNextMidnight()
    : null; // permanent for hitTag

  await safeBaseRef.set({
    id: safeBaseRef.key,
    location: location,
    type: type,
    createdAt: admin.database.ServerValue.TIMESTAMP,
    expiresAt: expiresAt
  });
}

function getNextMidnight() {
  const now = new Date();
  const midnight = new Date(now);
  midnight.setHours(24, 0, 0, 0);
  return midnight.getTime();
}
```

**Swift Code**:
```swift
func dropBomb(gameId: String, location: CLLocationCoordinate2D, tagType: TagType) async throws -> [TagResult] {
    let functions = Functions.functions()
    let callable = functions.httpsCallable("validateTag")

    let data: [String: Any] = [
        "gameId": gameId,
        "guessedLocation": [
            "latitude": location.latitude,
            "longitude": location.longitude
        ],
        "tagType": tagType.rawValue
    ]

    let result = try await callable.call(data)

    guard let resultData = result.data as? [String: Any],
          let results = resultData["results"] as? [[String: Any]] else {
        throw GameError.invalidResponse
    }

    return try results.map { try TagResult(from: $0) }
}
```

---

### 7. Push Notification Registration

**Legacy**:
```
POST /phoneTag.php?fn=updatePushnotification
Body: id={userId}&pnid={pushToken}

Response: "OK"
```

**Modern Firebase**:
```javascript
// Database path: /users/{userId}/pushTokens
{
  "tokens": {
    "token_abc123": {
      "token": "apns_token_here",
      "platform": "ios",
      "lastUpdated": 1234567890
    }
  }
}

// No Cloud Function needed - client writes directly
// Security rules ensure user can only write own tokens
```

**Swift Code**:
```swift
func registerPushToken(_ token: String) async throws {
    guard let userId = Auth.auth().currentUser?.uid else { return }

    let ref = Database.database().reference()
        .child("users/\(userId)/pushTokens/\(UUID().uuidString)")

    let tokenData: [String: Any] = [
        "token": token,
        "platform": "ios",
        "lastUpdated": ServerValue.timestamp()
    ]

    try await ref.setValue(tokenData)
}

// In AppDelegate:
func application(_ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

    Task {
        try await registerPushToken(tokenString)
    }
}
```

---

## Firebase Security Rules

### Complete Rules Structure
```javascript
{
  "rules": {
    // Users can only read/write their own data
    "users": {
      "$userId": {
        ".read": "$userId === auth.uid",
        ".write": "$userId === auth.uid"
      }
    },

    // Locations: users can only write own, but game participants can read
    "locations": {
      "$userId": {
        ".write": "$userId === auth.uid",
        "current": {
          ".read": "root.child('games').child($gameId).child('players').child(auth.uid).exists()"
        }
      }
    },

    // Games: participants can read, only cloud functions can write critical data
    "games": {
      "$gameId": {
        ".read": "root.child('games').child($gameId).child('players').child(auth.uid).exists()",

        // Only cloud functions can write to these
        "players": {
          "$playerId": {
            "strikes": {
              ".write": false
            },
            "isActive": {
              ".write": false
            }
          }
        },

        // Players can write their own bases
        "players": {
          "$playerId": {
            "homeBase1": {
              ".write": "$playerId === auth.uid"
            },
            "homeBase2": {
              ".write": "$playerId === auth.uid"
            }
          }
        }
      }
    },

    // Tags are write-only through cloud functions
    "tags": {
      ".read": false,
      ".write": false
    }
  }
}
```

---

## Cloud Functions Index

### Required Cloud Functions
```javascript
// functions/src/index.ts

// Game Management
exports.createGame = functions.https.onCall(createGameHandler);
exports.joinGame = functions.https.onCall(joinGameHandler);
exports.startGame = functions.https.onCall(startGameHandler);
exports.endGame = functions.https.onCall(endGameHandler);

// Tag System
exports.validateTag = functions.https.onCall(validateTagHandler);
exports.placeTripwire = functions.https.onCall(placeTripwireHandler);
exports.processTripwireCrossing = functions.https.onCall(processTripwireCrossingHandler);

// Scheduled Functions
exports.resetDailyTags = functions.pubsub
  .schedule('0 0 * * *') // Every midnight
  .timeZone('America/New_York')
  .onRun(resetDailyTagsHandler);

exports.cleanupExpiredBases = functions.pubsub
  .schedule('0 0 * * *')
  .timeZone('America/New_York')
  .onRun(cleanupExpiredBasesHandler);

// Purchases
exports.validatePurchase = functions.https.onCall(validatePurchaseHandler);

// Notifications
exports.sendGameInvite = functions.https.onCall(sendGameInviteHandler);
```

---

## Data Migration Strategy

### 1. Export Legacy Data
```sql
-- Export users
SELECT * FROM users;

-- Export games
SELECT * FROM games;

-- Export bombs/tags
SELECT * FROM bombs;

-- Export arsenal
SELECT * FROM user_arsenal;
```

### 2. Transform to Firebase Format
```javascript
// migration/transformUsers.js
const transformUser = (legacyUser) => ({
  userId: legacyUser.id,
  username: legacyUser.username,
  fullName: legacyUser.fullname,
  email: legacyUser.email,
  createdAt: new Date(legacyUser.created_at).getTime(),
  arsenal: {
    basicBombs: parseInt(legacyUser.basic_bombs) || 0,
    wideRadiusBombs: parseInt(legacyUser.wide_bombs) || 0,
    tripwires: parseInt(legacyUser.mines) || 0,
    extraBases: 0
  }
});
```

### 3. Import to Firebase
```javascript
// migration/importToFirebase.js
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.database();

async function importUsers(users) {
  const batch = {};

  for (const user of users) {
    const transformed = transformUser(user);
    batch[`users/${transformed.userId}`] = transformed;
  }

  await db.ref().update(batch);
  console.log(`Imported ${users.length} users`);
}
```

---

## Testing Strategy

### 1. Unit Tests for Cloud Functions
```javascript
// functions/test/validateTag.test.js
const test = require('firebase-functions-test')();

describe('validateTag', () => {
  it('should hit target within radius', async () => {
    const data = {
      gameId: 'test_game',
      guessedLocation: { latitude: 40.7128, longitude: -74.0060 },
      tagType: 'basic'
    };

    const result = await validateTag(data, { auth: { uid: 'user1' } });

    expect(result.results[0].result.type).toBe('hit');
  });

  it('should miss target outside radius', async () => {
    // Test miss scenario
  });

  it('should block tag if target in safe base', async () => {
    // Test safe base blocking
  });
});
```

### 2. Integration Tests
```javascript
// Test complete tag flow
it('should process full tag workflow', async () => {
  // 1. Create game
  const game = await createGame();

  // 2. Set home bases
  await setHomeBases(game.id, 'player1');
  await setHomeBases(game.id, 'player2');

  // 3. Drop bomb
  const result = await validateTag({
    gameId: game.id,
    guessedLocation: testLocation,
    tagType: 'basic'
  });

  // 4. Verify results
  expect(result).toBeDefined();
});
```

---

## Performance Considerations

### 1. Batch Writes
```javascript
// BAD: Multiple individual writes
for (const player of players) {
  await db.ref(`games/${gameId}/players/${player.id}`).set(playerData);
}

// GOOD: Single batch update
const updates = {};
for (const player of players) {
  updates[`games/${gameId}/players/${player.id}`] = playerData;
}
await db.ref().update(updates);
```

### 2. Denormalization
```javascript
// Denormalize frequently accessed data
{
  "games": {
    "game123": {
      "playerCount": 4,  // Cached value
      "players": { ... }
    }
  },
  "userGames": {
    "user456": {
      "game123": {
        "gameName": "Weekend Game",  // Denormalized
        "playerCount": 4,            // Denormalized
        "status": "active"           // Denormalized
      }
    }
  }
}
```

### 3. Indexing
```javascript
// Create indexes for common queries
{
  "rules": {
    ".indexOn": ["createdAt", "status"],
    "games": {
      ".indexOn": ["status", "createdBy"]
    }
  }
}
```

---

Use this guide to ensure all legacy API functionality is preserved while migrating to Firebase's modern, scalable architecture.

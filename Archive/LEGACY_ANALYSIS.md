# Phone Tag Legacy Codebase - Comprehensive UI/UX Analysis

> **Source**: `../phone-tag-legacy/phonetag/` (2012 Objective-C/UIKit iOS app)
> **Purpose**: This document guides all UI implementation in the modern SwiftUI rebuild.

---

## Table of Contents

1. [All Screens](#1-all-screens)
2. [Navigation Flow](#2-navigation-flow)
3. [Visual Design System](#3-visual-design-system)
4. [User Interaction Patterns](#4-user-interaction-patterns)
5. [Assets Inventory](#5-assets-inventory)
6. [Deprecated APIs & Modern Equivalents](#6-deprecated-apis--modern-equivalents)
7. [Data Models](#7-data-models)
8. [Custom UI Components](#8-custom-ui-components)

---

## 1. All Screens

### 1.1 Login Screen (`Login.h/m`)

**Purpose**: User authentication via username/password.

**When shown**: On app launch if no saved session exists.

**IBOutlets**:
| Outlet | Type | Purpose |
|--------|------|---------|
| `usernameField` | UITextField | Username input |
| `passwordField` | UITextField | Password input |
| `passwordLabel` | UILabel | Error/validation text |
| `loginLogo` | CSAnimationView | Animated logo (Canvas framework) |
| `registerButton` | UIButton | Navigate to registration |
| `forgotInfo` | UIButton | Password recovery |
| `loginLabel` | UILabel | Additional info label |
| `scrollView` | UIScrollView | Keyboard handling container |

**User actions**:
- Enter username and password
- Tap Login button to authenticate
- Tap Register to create account
- Tap "Forgot Info" for password recovery

**Fonts**:
- `usernameField`: `SFArchRival-Italic` 24pt, black placeholder
- `passwordField`: `SFArchRival-Italic` 24pt, black placeholder
- `passwordLabel`: `SFArchRival-Italic` 14pt
- `registerButton`: `SFArchRival-Italic` 12pt
- `forgotInfo`: `SFArchRival-Italic` 12pt

**Background images**: `loginBg.png`, `loginFields.png`, `loginLogo.png`, `loginButton.png`

**Validation behavior**:
- Empty fields: shows `passwordLabel` with error text
- Incorrect password: `loginLogo` shakes (CSAnimationTypeShake, 0.5s)
- Success: dismisses modal, navigates to home

**Keyboard handling**:
- `textFieldDidBeginEditing`: scroll to `field.frame.origin.y + 50` (animated)
- `textFieldDidEndEditing`: scroll back to `(0, 0)` (animated)

**Network**: POST to `phoneTag.php?fn=loginUser` with params `user`, `pw`, `token`
- Response 0: "No user found"
- Response 1: Incorrect password (triggers shake)
- Default: Success, parse user JSON

---

### 1.2 Registration Screen (`Registration.h/m`)

**Purpose**: New user account creation with real-time validation.

**When shown**: Tapping "Register" from Login screen (modal presentation).

**IBOutlets**:
| Outlet | Type | Purpose |
|--------|------|---------|
| `uNameField` | UITextField | Username (tag 1) |
| `uNameLabel` | UILabel | Username validation feedback |
| `fNameField` | UITextField | First name (tag 2) |
| `lNameField` | UITextField | Last name (tag 3) |
| `emailField` | UITextField | Email address (tag 4) |
| `emailLabel` | UILabel | Email validation feedback |
| `passwordField` | UITextField | Password (tag 5) |
| `passwordLabel` | UILabel | Password validation feedback |
| `scrollView` | UIScrollView | Keyboard offset container |
| `boxONE` | UIImageView | Decorative image |

**User actions**:
- Fill all fields (all required)
- Username validates against server in real-time
- Email validates format + uniqueness in real-time
- Password must be 5+ characters
- Tap Submit or Cancel

**Fonts**: All fields `SFArchRival-Italic` 24pt; all labels `SFArchRival-Italic` 14pt

**Background images**: `registerbg.png`, `registerFields.png`, `registerText.png`

**Real-time validation** (`textFieldDidEndEditing`):
- Username → `checkUsername` API. Response 1: "Username is already taken". Response 0: "Great choice!"
- Email → `checkEmail` API. Response 0: valid. Response 1: "already registered". Response 2: "not in email format"
- Password → length > 4

**Scroll offsets per field**:
- Tags 1-2: no scroll
- Tag 3: `y - 40`
- Tag 4: `y - 60`
- Tag 5: `y - 80`
- Reset to `(0, 0)` on end editing

**Navigation**: Segue `"registered"` on success; `dismissViewControllerAnimated:` on cancel

---

### 1.3 Home Screen / Game List (`ViewController.h/m`)

**Purpose**: Main menu showing all active and completed games, plus start/join options.

**When shown**: After successful login or app launch with saved session.

**IBOutlets**:
| Outlet | Type | Purpose |
|--------|------|---------|
| `listOfGames` | UITableView | Games table (2 sections) |
| `startGameBox` | UIImageView | "Start a Game" banner |
| `startButton` | UIButton | Create new game |
| `joinButton` | UIButton | Open code input modal |
| `codeInputBox` | UIView | 6-digit code entry container |
| `code1`-`code6` | UITextField | Individual code character inputs |
| `codeLabel` | UILabel | Code validation feedback |
| `checkRegistrationButton` | UIButton | Submit join code |
| `coverall` | UIView | Semi-transparent dimming overlay |
| `backgroundLogo` | UIImageView | ptLogo shown when no games |
| `refreshControl` | UIRefreshControl | Pull-to-refresh (white tint) |

**User actions**:
- View current and completed games
- Tap a game row to enter the game board
- Tap "Start Game" to create a new game
- Tap "Join Game" to enter a 6-character code
- Pull to refresh game list
- Swipe to delete/resign from a game
- Tap game code button to copy/share code
- Send SMS invites

**Table view layout**:
- **Section 0**: "Current Games" — header image `currentGames.png`, height 88pt
- **Section 1**: "Old Games" — header image `oldGames.png`, height 88pt
- Header view: (x:20, y:0, w:280, h:88)
- Section 0 footer: 55pt
- Section 1 footer: 20pt (if games) or 0pt
- Separator: pattern image `separatorLogo.png`
- Separator inset: `UIEdgeInsetsMake(0, 0, 30, 0)`
- Background: clear

**Game row cell layout**:
- Background: `gamerowbg.png`
- Per player (up to 5):
  - Player view: 60w x 134h
  - X position: `62 * player_index`
  - Y position: `3 + (5 * player_index)`
  - Name label: frame `(-45, 60, 117, 20)`, rotated -90deg (`M_PI / -2`)
  - Font: `SFArchRival-Italic` 18pt
  - Background shadow label offset: `(-44, 61)`
- Lives display: 5 hearts stacked vertically
  - Y: `7 + (i * 25)`, X: 30, Size: 22w x 20h
  - Active: `heart_{player_number}.png`
  - Lost: `lifelost.png`
  - Opacity: 0.3 if lives=0, else 1.0
- Game code button: `SFArchRival-Italic` 15pt
- Game title: `SFArchRival-Italic` 12pt
- Change indicator: red dot if state changed

**Player name colors** (consistent throughout app):
| Player | RGB | Color |
|--------|-----|-------|
| 1 | (237, 25, 105) | Pink/Magenta |
| 2 | (159, 204, 58) | Lime Green |
| 3 | (255, 198, 19) | Yellow/Gold |
| 4 | (111, 84, 164) | Purple |
| 5 | (52, 103, 177) | Blue |

**Code input animation**:
- Open (0.2s): codeInputBox → (0, 0), startGameBox slides up, joinButton slides right, coverall alpha → 0.8, auto-focus code1
- Close (0.2s): reverse of above, coverall alpha → 0.0
- Each field auto-advances to next on 1 character typed
- Error messages shown character-by-character (0.05s interval per char)
- After error: all fields reset to "*", refocus code1
- After 6 valid digits: show checkRegistrationButton

**Join responses**:
- 0: "No Game, Try another?!"
- 1: Success, reload games
- 2: "Game is full. Try another?!"
- 3: "You're already in this game!"

**Delete/resign alert**:
- 1 player confirmed: "Do you really want to delete this game?"
- 2+ players: "Do you really want to resign from this game?"
- Buttons: "Yes, I'm a quitter" / "Psh, I'm no quitter!"

**Version mismatch alert**: Checks all player versions match; offers "Tell them to update"

**Location tracking**: `kCLLocationAccuracyHundredMeters`, `kCLDistanceFilterNone`, updates every 120s timer

**SMS invite body**: `"Join my game of Phone Tag! Enter the game code: {CODE}"`

---

### 1.4 Start Game Screen (`StartGame.h/m`)

**Purpose**: Create a new game by selecting friends/contacts (2-5 players).

**When shown**: Tapping "Start Game" from Home screen (modal presentation).

**IBOutlets**:
| Outlet | Type | Purpose |
|--------|------|---------|
| `playersCollectionView` | UICollectionView | Selected players grid (1-4 cells) |
| `playersTableView` | UITableView | Available players to choose from |
| `friendsButton` | UIButton | Address book source toggle |
| `facebookButton` | UIButton | Facebook source toggle |
| `recentButton` | UIButton | Recent players source toggle |
| `numberHolder` | UIView | Player number icons (305w x 140h) |
| `tableLoader` | UIView | Loading indicator |
| `titleBox` | UIView | Game name entry container |
| `gameNameField` | UITextField | Game title input (max 8 chars) |
| `titleSubmitCancel` | UIButton | Cancel title entry |
| `titleSubmitButton` | UIButton | Submit game |
| `recentPlayersScroller` | UIScrollView | Horizontal recent players |

**User actions**:
- Switch between Friends/Facebook/Recent tabs
- Tap a player row to add them to the game
- Tap selected player to remove
- Enter game name (optional but prompted)
- Submit to create game

**Fonts**:
- `gameNameField`: `SFArchRival-Italic` 30pt, black tint
- Collection cell username: `BadaBoom BB` (variable sizes: 18pt, 28pt, 23pt, 26pt per cell index)
- Collection cell fullname: `SFArchRival-Italic` 11pt
- Table row: system font

**Tab button images**:
- `friendsOn.png` / `friendsOff.png`
- `fbOn.png` / `fbOff.png`
- `recentOn.png` / `recentOff.png`

**Player number icons** (in numberHolder):
- Player 1: (32, 26, 32, 45) — `player_1.png`
- Player 2: (180, 17, 32, 45) — `player_2.png`
- Player 3: (64, 90, 32, 45) — `player_3.png`
- Player 4: (210, 92, 32, 45) — `player_4.png`
- Icons hide as players are added

**Collection cell sizes** (variable per index):
| Cell Index | Width | Height |
|------------|-------|--------|
| 0 | 100 | 80 |
| 1 | 200 | 80 |
| 2 | 160 | 80 |
| 3 | 140 | 80 |

**Collection transform**: rotated `0.01 * M_PI` radians (slight tilt)

**Table view**:
- Header height: 55pt
- Background: `tableBackgroundSolid.png`
- Cell nib: `PlayerRow`
- Sorted alphabetically by name

**Data sources**:
1. **Friends** (Address Book): Extracts contacts with phone numbers, creates initials if no image, filters out 800/900 numbers, validates 10-digit numbers
2. **Recent players**: `phoneTag.php?fn=getRecentFriends` — returns username, name, email, id
3. **Facebook**: Commented out in code

**Title entry animation**:
- Open (0.3s): titleBox slides in from top, auto-focus gameNameField
- Close (0.3s): titleBox slides back up, clears field

**Submit flow**:
1. Validate `players.count > 0` (else "You haven't added anyone to the game!")
2. Show title entry box
3. Validate title `length > 0` (else "You need to give this game a title")
4. Show CCAlertView: "Are you ready to submit this game?" — "Yep" / "Oops, not yet!"
5. Generate 6-char code (A-Z 0-9 random)
6. SMS to non-registered players: `"Join my game '{gameName}' on phone tag so we can battle each other! Join a game with the registration number: {CODE}"`
7. POST to `phoneTag.php?fn=creategame` with params p1-p5, type, code, count, gamename
8. Segue `"startgame"` on success

**Max players**: 4 opponents (5 total including creator). Alert: "You can only add up to 4 players per game."

---

### 1.5 Game Board / Map View (`gameBoard.h/m`) — MOST COMPLEX SCREEN

**Purpose**: Core gameplay screen. Map showing game state, bomb placement, base setup, arsenal, player info, and activity feed.

**When shown**: Tapping a game from the Home screen game list.

**IBOutlets**:
| Outlet | Type | Purpose |
|--------|------|---------|
| `mapView` | MKMapView | Full-screen game map |
| `searchMap` | UISearchBar | Location geocoding search |
| `openSearch` | UIButton | Toggle search bar |
| `spinner` | UIActivityIndicatorView | Loading indicator |
| `itemHolder` | UIView | Arsenal button container |
| `bombDropSightOverlay` | UIView | Crosshair overlay for bombing |
| `bombButtonDropView` | UIView | Drop button container |
| `dropBombButton` | UIImageView | Animated drop button |
| `dropBomb` | UIButton | Confirm bomb drop action |
| `bombLabel` | UILabel | Bomb count display |
| `baseDropSightOverlay` | UIImageView | Crosshair for base placement |
| `dropBaseButton` | UIButton | Confirm base drop |
| `baseDropperHolder` | UIView | Base icons container (140w x 90h) |
| `dropBaseInstructions` | UITextView | Base placement instructions |
| `Base1`, `Base2` | UIImageView | Base status icons |
| `playerInfoContainer` | UIView | Slide-in player stats panel |
| `playerInfoBox` | UIView | Stats content |
| `feedBox` | UIView | Activity feed container |
| `arsenalCollection` | UICollectionView | Arsenal items carousel |
| `youreDead` | UIView | Elimination overlay |
| `directions` | UILabel | Instructions text |
| `timeBackground` | UIImageView | Top status bar |

**User actions**:
- Pan/zoom map to explore
- Search for locations via search bar
- Tap "reorient" button to center on current location
- Select items from arsenal carousel
- Drag bomb/tag to target location
- Drop home bases (2 required at game start)
- View player info panel (slides in/out)
- View activity feed
- Place tripwires/mines at current location

**Fonts**:
- `bombLabel`: `SFArchRival-Italic` 28pt
- Bomb count "x" label: `SFArchRival-Italic` 14pt
- Hit result labels: `SFArchRival-Italic` 17pt, white, center-aligned
- `dropBaseInstructions`: `BadaBoom BB` 14pt

**Player colors** (gameboard variant — slightly different from home screen):
| Player | RGB | Color |
|--------|-----|-------|
| 1 | (237, 28, 36) | Red |
| 2 | (0, 174, 239) | Cyan/Blue |
| 3 | (255, 242, 0) | Yellow |
| 4 | (178, 30, 142) | Magenta |
| 5 | (178, 210, 53) | Lime |

**Map configuration**:
- User location: enabled
- Points of interest: disabled
- Desired accuracy: `kCLLocationAccuracyNearestTenMeters`
- Distance filter: `kCLDistanceFilterNone`
- Monitoring: significant location changes
- Default zoom span: lat 0.007, lng 0.007 (~1 city block)

**Map overlays** (custom `gameboardOverlay` class):

| Type | Image Pattern | Size | Opacity | Notes |
|------|--------------|------|---------|-------|
| User location | `userLoc_{N}.png` | 1200x1200 | 1.0 | Current player position |
| Home base | `base_{N}.png` | 2000x2000 | 1.0 | Per-player colored |
| Bomb/tag | `bomb_{N}.png` | 2000x2000 | Varies | Fades over 3+ days (1.0→0.1) |
| Hit result | `hit_{N}.png` | 2000x2000 | 1.0 | Permanent marker |
| Tripwire | `tripLine_{N}.png` | 2000x2000 | 1.0 | Mine/tripwire marker |
| Recon circle | MKCircle | 320m radius | — | Fill: RGB(36,255,0) 40%; Stroke: RGB(255,213,0) 1pt |

**Loading door animation** (on game board entry):
- Top door: (0, 0, screenWidth, screenHeight/2 + 79) with `topDoor.png`
  - Contains "initializing" image at (19, 148, 288, 122)
- Bottom door: (0, screenHeight/2 - 25, screenWidth, screenHeight/2 + 25) with `bottomDoor.png`
- Open animation (2.2s): top slides up off screen, bottom slides down
- Triggered when: myLocationUpdated AND annotationsUpdated both true

**Bomb drop flow**:
1. User taps bomb item in arsenal collection
2. Bomb dropper UI appears with crosshairs in map center
3. Bomb drop overlay animates in (0.5s alpha → 1.0, then slide X: -20)
4. User pans map to target location (crosshairs stay centered)
5. Tap "Drop Bomb" button
6. Screen coordinates converted to map coordinates via `convertPoint:toCoordinateFromView:`
7. **Client-side validation**: Can't bomb same location twice in same day, can't bomb within 0.1 miles of any base
8. Bomb animation plays (25 frames: `bomb animation_4.png` to `_28.png`, 1s duration)
9. POST to `phoneTag.php?fn=dropBomb` with gameid, lat, longi, userid, type
10. Results displayed in overlay

**Bomb button animation**: 23 frames (`boom_btn_0.png` to `_22.png`), 1s duration, loops continuously

**Base setup flow**:
1. Hides itemHolder and playerInfoContainer
2. Shows baseDropperHolder, baseDropSightOverlay, dropBaseButton
3. Creates 2 base icons at (5,15) and (72,15), size 60x60
4. User taps to place base at crosshair location
5. After 2 bases placed: POST to `phoneTag.php?fn=dropBase`
6. Close animation: 0.5s fade out
7. Alert: "You've placed your bases... When everyone else has set up their bases, the game can begin!"

**Hit results display**:
- Container: black background, alpha 0.8
- Background image: `hitResultBlast.png`
- Result rows: 28pt height, black alpha 0.9
- Messages: "You hit yourself!", "You hit {username}!", "You hit and killed {username}!"
- Dismiss: tap anywhere

**Recon feature**: Shows 3 MKCircles (320m radius) — actual location + 2 random nearby

**Player info container**:
- Closed position: Y: -298
- Open position: Y: 20
- Animation: 0.2s EaseOut
- Contains: PlayersInfo table + FeedTable

**Winner display**:
- Container: rotated square, size screenHeight x 1.5, spinning (0.1 rotations/s)
- Background: `winbg_2.png`
- Winner box: `winnerCloud.png` (305w x 259h)
- Title: `BadaBoom BB` 60-70pt, black
- Messages: "YOU WON!" / "{Username} Wins!" / "DRAW!"
- Animation: rotation + scale pulse (0.8s, infinite)

**Arsenal items**: IDs 1 (basic bomb), 2 (mine/tripwire), 3 (recon)
- Cell shows: item image (via SDWebImage), count (`SFArchRival-Italic` 16pt), "x" label (11pt), name
- Disabled cells: alpha 0.4 if count = 0

---

### 1.6 Arsenal / Store Screen (`Arsenal.h/m`)

**Purpose**: View owned items and purchase new ones via IAP.

**When shown**: Tapping Arsenal button from bottom nav, or from game board.

**IBOutlets**:
| Outlet | Type | Purpose |
|--------|------|---------|
| `arsenalCollectionView` | UICollectionView | User's owned items grid |
| `arsenalTableView` | UITableView | Store/purchasable items list |
| `arsenalInfoBox` | UIView | Item detail popup modal |

**User actions**:
- Browse owned items in collection
- Browse store items in table
- Tap item for details
- Purchase items via StoreKit
- Restore purchases
- Close arsenal

**Collection view**:
- Background: clear
- Transform: rotated `M_PI * 0.01` (slight tilt)
- Cell: `PlayerArsenalCell`
- Shows: item image, count (`SFArchRival-Italic` 16pt), "x" (11pt), name

**Table view**:
- Background: clear
- Cell: `ArsenalRow`
- Header height: 175pt, image `addtoarsenal.png` (275w x 105h at offset 23, 40)
- Cell data: itemName, itemCount, itemQuantity, itemId, userid
- Buy button with Apple product ID

**Detail popup**: `ArsenalDetails` nib, populated by `buildArsenalInfo:` method

**Navigation**: Dismisses on close; detail box closes first if open

---

### 1.7 Players Info Panel (`PlayersInfo.h/m`)

**Purpose**: Displays detailed player statistics within an active game.

**When shown**: Sliding panel within Game Board (triggered by tapping player info area).

**Table view**: Custom `PlayersInfoRow` nib cells

**Cell layout per player**:
| Element | Property | Notes |
|---------|----------|-------|
| `userName` | Username | Color-coded by player index |
| `userNameBg` | Shadow label | Same text, offset for depth |
| `playerName` | Full name | |
| `playerLives` | Lives count | |
| `playerBombs` | Bombs remaining | |
| `bombView` | Image | `bombsX_{index+1}.png` |
| `livesView` | Image | `livesX_{index+1}.png` |

**Player colors** (same as home screen):
- Index 0: RGB(237, 25, 105) — Pink
- Index 1: RGB(159, 204, 58) — Lime
- Index 2: RGB(255, 198, 19) — Yellow
- Index 3: RGB(111, 84, 164) — Purple
- Index 4: RGB(52, 103, 177) — Blue

---

### 1.8 Activity Feed (`FeedTable.h/m`)

**Purpose**: Shows game events and player actions chronologically.

**When shown**: Within Game Board player info container, alongside PlayersInfo.

**Table view**: Custom `FeedRow` nib cells

**Data loading**: `phoneTag.php?fn=getFeed` (POST: gid, uid)

**Response fields per item**:
- `message`: text (not used directly)
- `html`: HTML string rendered in UIWebView
- `date`: timestamp for sorting (descending)

**Cell**: `feedWebView` (UIWebView) — user interaction disabled, auto-sized to content

---

## 2. Navigation Flow

### 2.1 Navigation Hierarchy

```
App Launch
│
├─ No Session ──────────────────── Login Screen
│                                     │
│                                     ├── Register Screen (modal)
│                                     │     └── Success → Login Screen
│                                     │
│                                     └── Login Success → Home Screen
│
└─ Has Session ──────────────────── Home Screen (Game List)
                                      │
                                      ├── "Start Game" → Start Game Screen (modal)
                                      │     └── Submit → Home Screen (game created)
                                      │
                                      ├── "Join Game" → Code Input (overlay on Home)
                                      │     └── Valid Code → Home Screen (game joined)
                                      │
                                      ├── Tap Game Row → Game Board (push/segue)
                                      │     │
                                      │     ├── Arsenal Button → Arsenal Screen (modal)
                                      │     │
                                      │     ├── Player Info → PlayersInfo Panel (slide-in)
                                      │     │
                                      │     ├── Feed → FeedTable Panel (slide-in)
                                      │     │
                                      │     └── Back → Home Screen
                                      │
                                      ├── Arsenal Button → Arsenal Screen (modal)
                                      │
                                      └── Settings → Settings Screen
```

### 2.2 Navigation Patterns

- **All major transitions are MODAL** (no UINavigationController detected)
- Login → Registration: modal present
- Home → Start Game: modal present
- Home → Game Board: storyboard segue (push-style)
- Game Board → Arsenal: modal present
- Player Info / Feed: slide-in panel (not modal, animated constraint change)
- Join Game: overlay on Home screen (not a separate VC)
- All dismissals: `dismissViewControllerAnimated:YES`

### 2.3 Screen Presentation Styles

| Transition | Type | Duration |
|-----------|------|----------|
| Login → Home | Modal dismiss | default |
| Home → Start Game | Modal present | default |
| Home → Game Board | Storyboard segue | default |
| Game Board → Arsenal | Modal present | default |
| Code input appear | Custom animation | 0.2s |
| Code input dismiss | Custom animation | 0.2s |
| Player info slide in | Constraint animation | 0.2s EaseOut |
| Player info slide out | Constraint animation | 0.2s EaseOut |
| Base setup appear | Alpha animation | 0.5s |
| Base setup dismiss | Alpha animation | 0.5s |
| Bomb overlay appear | Alpha + slide | 0.5s |
| Door open (loading) | Slide top/bottom | 2.2s |
| Title entry appear | Slide from top | 0.3s |

---

## 3. Visual Design System

### 3.1 Color Palette

**Player Colors** (used throughout the entire app for identification):

| Player # | Name | RGB | Hex | Usage |
|----------|------|-----|-----|-------|
| 1 | Pink/Magenta | (237, 25, 105) | #ED1969 | Names, hearts, bases, bombs |
| 2 | Lime Green | (159, 204, 58) | #9FCC3A | Names, hearts, bases, bombs |
| 3 | Yellow/Gold | (255, 198, 19) | #FFC613 | Names, hearts, bases, bombs |
| 4 | Purple | (111, 84, 164) | #6F54A4 | Names, hearts, bases, bombs |
| 5 | Blue | (52, 103, 177) | #3467B1 | Names, hearts, bases, bombs |

**Game Board Player Colors** (alternate palette used specifically on the map):

| Player # | RGB | Hex | Notes |
|----------|-----|-----|-------|
| 1 | (237, 28, 36) | #ED1C24 | More red than pink |
| 2 | (0, 174, 239) | #00AEEF | Cyan instead of green |
| 3 | (255, 242, 0) | #FFF200 | Brighter yellow |
| 4 | (178, 30, 142) | #B21E8E | Brighter magenta |
| 5 | (178, 210, 53) | #B2D235 | Lime green |

**Map Overlay Colors**:
| Element | Fill | Stroke |
|---------|------|--------|
| Recon circle | RGB(36, 255, 0) 40% alpha | RGB(255, 213, 0) 1pt |
| Hit result bg | Black 80% alpha | — |
| Hit result row | Black 90% alpha | — |

**UI Colors**:
- Status bar: Light content (white text) on all screens
- Overlay dimming: black 80% alpha
- Text placeholders: black
- Backgrounds: image-based (not solid colors)

### 3.2 Typography

**Font Families**:
1. **SF Arch Rival Italic** (`SFArchRival-Italic`) — Primary game font, comic/action style
2. **BadaBoom BB** (`BadaBoom BB` / `BADABB__.TTF`) — Secondary font, comic/explosion style

**Font Usage by Size**:

| Size | Font | Where Used |
|------|------|-----------|
| 70pt | BadaBoom BB | Winner announcement title |
| 60pt | BadaBoom BB | Winner announcement (shorter text) |
| 46pt | SFArchRival-Italic | 6-digit code input characters |
| 30pt | SFArchRival-Italic | Game name input field |
| 28pt | SFArchRival-Italic | Bomb count on game board |
| 26pt | BadaBoom BB | Player collection cell (index 3) |
| 24pt | SFArchRival-Italic | Login/register input fields, code validation label |
| 23pt | BadaBoom BB | Player collection cell (index 2) |
| 18pt | SFArchRival-Italic | Player names on game rows (rotated), BadaBoom for cell 0 |
| 17pt | SFArchRival-Italic | Hit result labels |
| 16pt | SFArchRival-Italic | Arsenal item count |
| 15pt | SFArchRival-Italic | Game code button |
| 14pt | SFArchRival-Italic | Validation labels, bomb "x", BadaBoom for base instructions |
| 12pt | SFArchRival-Italic | Register/forgot buttons, game title |
| 11pt | SFArchRival-Italic | Collection fullname, arsenal "x" label |

### 3.3 Layout & Spacing

**Screen dimensions** (iPhone 5/SE era): 320w x 568h

**Key measurements**:
| Element | Dimension |
|---------|-----------|
| Status bar height | 32pt (hidden on most screens) |
| Bottom navigation bar | 56pt |
| Table section header | 88pt |
| Game list row height | 234pt |
| Player view in game row | 60w x 134h |
| Heart icon | 22w x 20h |
| Heart vertical spacing | 25pt |
| Base dropper container | 140w x 90h |
| Base icons in dropper | 60w x 60h |
| Arsenal header | 175pt (table), contains 275w x 105h image |
| Player info panel (closed) | Y: -298 |
| Player info panel (open) | Y: 20 |
| Winner cloud | 305w x 259h |
| Player number icons | 32w x 45h each |
| Map zoom span | lat 0.007, lng 0.007 |
| Bomb animation frame | 320w x 576h |

### 3.4 Custom UI Components

**outlinedLabel / outlinedLabelBold / outlinedLabelHeavy**:
- Custom UILabel subclasses that render text with a stroke/outline
- Three weight variants
- Used for player names to ensure readability on images/maps
- Creates visual depth with "shadow" background labels

**gameboardOverlay + gameBoardOverlayView**:
- Custom MKOverlay + MKOverlayRenderer pair
- Renders images on the map at specified coordinates
- Properties: coordinate, flagImage (filename), size, type, opacity
- `boundingMapRect` calculates display rect from size + coordinate
- Renderer draws image scaled to overlay's rect

**mapAnnotations**:
- Custom MKAnnotation with extended properties
- Stores: coordinate, title, subtitle (also image name), pinImage, type, userID, noteNumber, noteDistance

---

## 4. User Interaction Patterns

### 4.1 How Do Users Tag Someone? (Step-by-Step)

1. **Enter game board** by tapping a game from the home screen
2. **Loading sequence**: Door animation slides open (2.2s), revealing the map
3. **Browse arsenal** in the bottom collection view
4. **Select a bomb** by tapping it in the arsenal (must have count > 0)
5. **Crosshairs appear** in the center of the map
6. **Pan the map** to move the crosshairs to where you think the opponent is
   - The crosshairs stay fixed at screen center
   - The map moves underneath
7. **Tap "Drop Bomb" button** to confirm placement
8. **Client validates**: checks it's not too close to a base or duplicate location
9. **Bomb animation plays**: 25-frame explosion (1 second)
10. **Server calculates**: distance from guess to target's actual location
11. **Result shown**: Hit overlay appears with results
    - Hit: "You hit {username}!" — target loses 1 life, permanent safe base created
    - Miss: "Missed!" — temporary safe base created at guessed location
    - Kill: "You hit and killed {username}!" — target eliminated
12. **Tap anywhere** to dismiss result overlay

### 4.2 How Are Results Displayed?

**Hit Results Overlay**:
- Black semi-transparent background (80% alpha)
- `hitResultBlast.png` background image
- Each result in a row (28pt height, black 90% alpha)
- White text, `SFArchRival-Italic` 17pt, centered
- Tap gesture anywhere to dismiss

**Winner Screen**:
- Full-screen spinning background (`winbg_2.png`)
- Cloud graphic centered (`winnerCloud.png` 305x259)
- Large text: `BadaBoom BB` 60-70pt
- Continuous rotation + scale pulse animation

### 4.3 Gestures Used

| Gesture | Screen | Action |
|---------|--------|--------|
| Tap | All | Button presses, item selection |
| Pan | Game Board | Move map under crosshairs |
| Pinch | Game Board | Zoom map (custom annotation scaling) |
| Pull down | Home | Refresh game list |
| Swipe left | Home | Delete/resign from game |
| Tap (map) | Game Board | Place base at crosshair location |
| Tap anywhere | Hit results | Dismiss results overlay |
| Type | Code input | Auto-advance to next digit field |

### 4.4 Home Base Setup Flow

1. Game is in "waiting" status — player hasn't placed bases yet
2. Game board shows base dropper interface:
   - itemHolder and playerInfoContainer are hidden
   - baseDropperHolder visible with 2 base icons (60x60 each)
   - baseDropSightOverlay (crosshairs) visible
   - dropBaseButton visible
   - Instructions shown in `dropBaseInstructions`
3. User moves map to first base location
4. Tap drop button → Base 1 icon fills in
5. User moves map to second base location
6. Tap drop button → Base 2 icon fills in
7. Both bases sent to server (comma-separated coords)
8. Interface fades out (0.5s)
9. Alert: "You've placed your bases... When everyone else has set up their bases, the game can begin!"
10. Game remains in "waiting" until all players have placed 2 bases

### 4.5 Tripwire/Mine Placement

1. Select mine item from arsenal (item ID 2)
2. Confirmation alert: "Are you sure you want to place a mine here?"
3. Mine placed at USER'S CURRENT LOCATION (not a map selection)
4. POST to server with type=2
5. Overlay `tripLine_{playerNumber}.png` added to map

### 4.6 Recon Usage

1. Select recon item from arsenal (item ID 3)
2. Confirmation alert
3. Server returns: target's actual location + 2 random nearby points
4. 3 MKCircles drawn (320m radius each)
5. Map centers on middle point with wider span (0.05)
6. Player must guess which circle contains the actual target

---

## 5. Assets Inventory

### 5.1 All PNG Images (Excluding Animation Frames)

#### Authentication
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `loginBg.png` | Login background | Keep (custom art) |
| `loginFields.png` | Text field container | Redesign in SwiftUI |
| `loginLogo.png` | App logo | Keep (brand asset) |
| `loginButton.png` | Login button image | Redesign in SwiftUI |
| `registerbg.png` | Registration background | Keep (custom art) |
| `registerFields.png` | Registration fields bg | Redesign in SwiftUI |
| `registerText.png` | "Register" header text | Redesign in SwiftUI |

#### Game List
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `currentGames.png` | Section header | Redesign as text |
| `oldGames.png` | Section header | Redesign as text |
| `gamerowbg.png` | Game row background | Redesign in SwiftUI |
| `gameTitlebg.png` | Title background | Redesign in SwiftUI |
| `ptLogo.png` | Empty state logo | Keep (brand asset) |
| `separatorLogo.png` | Table separator | Redesign in SwiftUI |

#### Start Game
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `startAGame.png` | Start game banner | Redesign as text |
| `joinAGame.png` | Join game banner | Redesign as text |
| `startBackground.png` | Background | Keep (custom art) |
| `friendsOn.png` / `friendsOff.png` | Tab toggle | `person.2.fill` / `person.2` |
| `fbOn.png` / `fbOff.png` | Facebook tab | Remove (deprecated) |
| `recentOn.png` / `recentOff.png` | Recent tab | `clock.fill` / `clock` |
| `playerBlocks.png` | Player grid bg | Redesign in SwiftUI |
| `player_1.png` through `player_4.png` | Player number icons | Use numbered circles |
| `namegame.png` | Name field bg | Redesign in SwiftUI |
| `submit.png` | Submit button | Redesign in SwiftUI |
| `joinButton.png` | Join button | Redesign in SwiftUI |
| `playButton.png` | Play button | `play.fill` |

#### Game Board — Map UI
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `background.png` | General background | Keep |
| `crosshairs.png` / `@2x` | Bomb targeting reticle | Keep (custom game art) |
| `mapBack.png` | Back button on map | `chevron.left` |
| `searchMap.png` | Search icon | `magnifyingglass` |
| `reorient.png` | Re-center on user | `location.fill` |
| `bombLocationDropper.png` | Bomb dropper icon | Keep (custom game art) |
| `baseLocationDropper.png` | Base dropper icon | Keep (custom game art) |
| `baseDropBackground.png` | Base drop overlay bg | Redesign in SwiftUI |
| `dropBombCommand.png` | Drop instruction | Keep or redesign |
| `hitResultBlast.png` | Hit result background | Keep (custom game art) |
| `topDoor.png` | Loading animation top | Keep (custom game art) |
| `bottomDoor.png` | Loading animation bottom | Keep (custom game art) |
| `initializing.png` | Loading text | Redesign as text |
| `timeBg.png` | Status bar bg | Redesign in SwiftUI |
| `goText.png` | "GO" text | Redesign as text |

#### Player-Colored Assets (1 through 5 for each)
| Pattern | Purpose | Keep? |
|---------|---------|-------|
| `userLoc_{N}.png` | Player location pin | Keep (custom per-player) |
| `base_{N}.png` | Home base marker | Keep (custom per-player) |
| `bomb_{N}.png` | Bomb/tag marker | Keep (custom per-player) |
| `missile_{N}.png` + `@2x` | Missile icon | Keep (custom per-player) |
| `flag_{N}.png` | Flag marker | Keep (custom per-player) |
| `heart_{N}.png` | Life heart | Keep (custom per-player) |
| `hit_{N}.png` | Hit marker | Keep (custom per-player) |
| `bomb_btn_{N}.png` | Bomb button | Keep (custom per-player) |
| `bombsX_{N}.png` | Bomb counter | Keep (custom per-player) |
| `livesX_{N}.png` | Lives counter | Keep (custom per-player) |
| `tripLine_{N}.png` | Tripwire line | Keep (custom per-player) |

#### Arsenal / Store
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `arsenal.png` | Arsenal nav button | `bag.fill` |
| `arsenalBg.png` | Arsenal background | Keep |
| `arsenalblue.png` | Blue variant | Keep |
| `arsenalSmallBg.png` | Small bg | Keep |
| `arsenalTextBg.png` | Text background | Keep |
| `arsenalTop.png` | Top banner | Keep |
| `addtoarsenal.png` | "Add to Arsenal" header | Redesign as text |
| `bombBg.png` | Bomb item bg | Keep |

#### Standalone Game Elements
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `flag.png` | Generic flag | `flag.fill` |
| `mine.png` | Mine/trap icon | Keep (custom game art) |
| `tripWire.png` | Tripwire overlay | Keep (custom game art) |
| `lifelost.png` | Lost life (explosion) | Keep (custom game art) |
| `comicStrip.png` | Comic elements | Keep |
| `reconIcon.png` | Recon feature icon | `binoculars.fill` |

#### UI Chrome
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `bottomBox.png` | Bottom nav bar bg | Redesign in SwiftUI |
| `tableBackground.png` | Table bg | Redesign in SwiftUI |
| `tableBackgroundSolid.png` | Solid table bg | Redesign in SwiftUI |
| `settings.png` | Settings button | `gearshape.fill` |
| `cancelCode.png` | Cancel button | `xmark.circle.fill` |
| `updates.png` | Update badge | `circle.fill` (red) |
| `testing.png` | Testing indicator | Remove |
| `winbg_2.png` | Winner bg | Keep (custom art) |
| `winnerCloud.png` | Winner cloud | Keep (custom art) |
| `statsBg.png` | Stats background | Keep |

#### Tab Bar Icons
| Filename | Purpose | SF Symbol Alternative |
|----------|---------|----------------------|
| `user_tab@2x.png` | User tab | `person.fill` |
| `user_tab_player@2x.png` | Player tab | `person.2.fill` |

### 5.2 Animation Frame Sequences

**Bomb Explosion** (`BOOOM/`): `bomb animation_4.png` through `bomb animation_29.png` (26 frames)
- Used when: bomb/tag is placed on map
- Duration: 1 second, plays once
- Frame size: 320w x 576h
- **Recommendation**: Convert to Lottie animation or keep as frame sequence

**Boom Button** (`boomBtn/`): `boom_btn_0.png` through `boom_btn_23.png` (24 frames)
- Used when: drop bomb button is in active state
- Duration: 1 second, loops continuously
- **Recommendation**: Convert to Lottie animation

### 5.3 App Icons

Located in `App Icon [Rounded]/`:
- `Icon.png` / `@2x` — Standard app icon
- `Icon-Small.png` / `@2x` — Spotlight/settings
- `Icon-76.png` / `@2x` — iPad
- `Icon-Small-50.png` / `@2x` — iPad spotlight
- `iTunesArtwork.png` / `@2x` — App Store

### 5.4 Custom Fonts

| Font File | Family Name | Usage |
|-----------|-------------|-------|
| `SF Arch Rival Italic.ttf` | SFArchRival-Italic | Primary game font |
| `BADABB__.TTF` | BadaBoom BB | Secondary title font |

### 5.5 XIB Files (Interface Builder)

| XIB | Purpose | Maps to Modern |
|-----|---------|----------------|
| `ArsenalCell.xib` | Arsenal item cell | SwiftUI View |
| `ArsenalDetails.xib` | Item detail popup | SwiftUI sheet |
| `ArsenalRow.xib` | Store item row | SwiftUI View |
| `FeedRow.xib` | Feed event cell | SwiftUI View |
| `FeedTable.xib` | Feed table container | SwiftUI List |
| `GameListRow.xib` | Game row in home list | SwiftUI View |
| `PlayerRow.xib` | Player selection row | SwiftUI View |
| `PlayersInfo.xib` | Player stats panel | SwiftUI View |
| `PlayersInfoRow.xib` | Player info row | SwiftUI View |

---

## 6. Deprecated APIs & Modern Equivalents

### 6.1 UI Framework

| Legacy (iOS 6 UIKit) | Modern (iOS 17+ SwiftUI) | Notes |
|-----------------------|--------------------------|-------|
| `UIViewController` | `struct View: View` | MVVM with @Observable |
| `UITableView` + delegates | `List` / `ForEach` | Declarative data binding |
| `UICollectionView` + delegates | `LazyVGrid` / `LazyHGrid` | SwiftUI layout |
| `UIAlertView` | `.alert()` modifier | Deprecated since iOS 9 |
| `UIActionSheet` | `.confirmationDialog()` modifier | |
| `UIScrollView` (keyboard) | Automatic keyboard avoidance | SwiftUI handles this |
| `MKMapView` + delegates | `Map` with `MapContentBuilder` | New MapKit API |
| `MKPointAnnotation` | `Annotation` view builder | |
| `MKCircle` + renderer | `MapCircle` | |
| `MKPolyline` + renderer | `MapPolyline` | |
| `UIWebView` | `WKWebView` or SwiftUI `Text` | UIWebView removed in iOS 12 |
| XIB / Storyboard | SwiftUI declarative views | |
| `UIRefreshControl` | `.refreshable` modifier | |

### 6.2 Data & Networking

| Legacy | Modern | Notes |
|--------|--------|-------|
| `NSURLSession` + completion handlers | `async/await` + `URLSession` | Swift concurrency |
| `NSJSONSerialization` | `Codable` / `JSONDecoder` | Type-safe decoding |
| `NSUserDefaults` | `@AppStorage` / SwiftData | For persistence |
| Custom PHP REST API | Firebase Realtime Database + Cloud Functions | Real-time sync |
| POST with form encoding | Firebase SDK methods | Type-safe API |
| Polling for updates | Firebase `.observe()` listeners | Real-time |
| HTTP (not HTTPS) | HTTPS (mandatory since ATS) | Security |

### 6.3 Authentication

| Legacy | Modern | Notes |
|--------|--------|-------|
| Username/password (custom server) | Firebase Auth (Phone / Apple Sign-In) | Industry standard |
| Facebook Login SDK | Sign in with Apple (required by App Store) | Facebook optional |
| `NSUserDefaults` session storage | Firebase Auth token management | Automatic refresh |

### 6.4 Location Services

| Legacy | Modern | Notes |
|--------|--------|-------|
| `kCLDistanceFilterNone` | `distanceFilter = 100` | Battery preservation |
| `startUpdatingLocation` always | `startMonitoringSignificantLocationChanges` | Battery efficient |
| Manual timer-based uploads (240s) | Significant location change + background task | System-managed |
| `CLRegion` (deprecated) | `CLCircularRegion` | For geofencing |
| `requestAlwaysAuthorization` first | Request "When In Use" first, "Always" only when needed | Privacy best practice |
| `UIRemoteNotificationType` | `UNUserNotificationCenter` | UserNotifications framework |

### 6.5 Payments

| Legacy | Modern | Notes |
|--------|--------|-------|
| StoreKit 1 (`SKProductsRequest`) | StoreKit 2 (`Product.products()`) | Async/await native |
| `SKPaymentQueue` observer | `Transaction.updates` async stream | |
| Manual receipt validation | Server-side with `Transaction.jwsRepresentation` | |

### 6.6 Other

| Legacy | Modern | Notes |
|--------|--------|-------|
| `ABAddressBook` | `CNContactStore` (Contacts framework) | Address book deprecated iOS 9 |
| `MFMessageComposeViewController` | Same (still current) OR share sheet | SMS still uses this |
| `AudioServicesPlaySystemSound` | Same (still current) | For vibration/sounds |
| `dispatch_async(main_queue)` | `@MainActor` / `await MainActor.run` | Swift concurrency |
| `dispatch_sync` | `actor` isolation | Sendable + actors |
| `performSelectorOnMainThread:` | `@MainActor` | |
| Singleton pattern (`sharedManager`) | `@Dependency` (swift-dependencies) | Testable DI |
| `NSNotificationCenter` | Combine publishers or Observation framework | |
| `NSTimer` (polling) | `Task.sleep` / Timer.publish | Structured concurrency |
| Canvas framework (CSAnimationView) | SwiftUI animations / `.animation()` | Built-in |
| SDWebImage | AsyncImage or SwiftUI `.task` + URLSession | Built-in async images |

---

## 7. Data Models

### 7.1 PTStaticInfo (Singleton → UserSession)

**Legacy** (`PTStaticInfo.h/m`):
- Singleton via `[PTStaticInfo sharedManager]`
- Persists to NSUserDefaults
- Properties: ptFullname, ptId, ptUsername, ptEmail, activeGameId, ptVersion, ptArsenalArray
- Methods: username:fullname:email:PTId:PTv:, arsenal:, addVersion:, logout

**Modern equivalent**: Firebase Auth + `@Observable` UserSession with `@Dependency` injection

### 7.2 aGame (Game State)

**Legacy** (`aGame.h/m`):
- All properties are NSString (even numeric values)
- Properties: lives, bombsLeft, lastLocLat, lastLocLongi, lastLogin, alive, totalPlayers, players (NSArray), player5Bases, winner, gametype, regCode, initiated

**Modern equivalent**: Strongly-typed `Game` struct with `Codable` + `Sendable`

### 7.3 aBomb (Tag/Bomb)

**Legacy** (`aBomb.h/m`):
- Properties: bombId, gameid, lat, longi, userid, type, radius, hits (NSArray), dateBombed

**Modern equivalent**: `Tag` struct per CLAUDE.md specification

---

## 8. Custom UI Components

### 8.1 Outlined Labels

Three classes: `outlinedLabel`, `outlinedLabelBold`, `outlinedLabelHeavy`

**Purpose**: Render text with a visible stroke/outline for readability on images and maps.

**Implementation pattern**: Custom `drawTextInRect:` that draws text multiple times with offset for stroke effect.

**Modern approach**:
```swift
// SwiftUI equivalent
Text("Player Name")
    .font(.custom("SFArchRival-Italic", size: 18))
    .foregroundStyle(.white)
    .shadow(color: .black, radius: 0, x: 1, y: 1)
    .shadow(color: .black, radius: 0, x: -1, y: -1)
    .shadow(color: .black, radius: 0, x: 1, y: -1)
    .shadow(color: .black, radius: 0, x: -1, y: 1)
// Or use strokeBorder overlay technique for true outlined text
```

### 8.2 Custom Map Overlays

**gameboardOverlay** (MKOverlay):
- `coordinate`: CLLocationCoordinate2D
- `flagImage`: NSString (image filename)
- `size`: CGSize
- `type`: NSString ("userLoc", "base", "bomb", etc.)
- `opacity`: float
- `boundingMapRect`: calculated from size + coordinate

**gameBoardOverlayView** (MKOverlayRenderer):
- Draws the image scaled to the overlay's map rect
- Used for all game objects on the map

**Modern approach**: SwiftUI `Map` with `Annotation` view builders and `MapCircle`/`MapPolyline`

### 8.3 Map Annotations

**mapAnnotations** (MKAnnotation):
- Extended with: pinImage, type, userID, noteNumber, noteDistance, cites

**Modern approach**: Custom `Identifiable` structs used directly in `Map` content builder

---

## Summary: What to Preserve vs. Modernize

### MUST PRESERVE (Core UX)
- 6-character join codes
- 2 home bases requirement before game starts
- Crosshairs-based tag/bomb placement (map moves, crosshairs stay centered)
- Arsenal carousel at bottom of game board
- Player color system (5 distinct colors)
- Hearts for lives display
- Outlined text labels for readability
- Loading door animation concept
- Hit/miss result overlay
- Sliding player info panel
- Geofencing for tripwires
- Comic book/action aesthetic

### MODERNIZE (Technology)
- UIKit → SwiftUI
- Objective-C → Swift 6 (strict concurrency)
- Custom PHP API → Firebase (Auth + Realtime DB + Cloud Functions)
- NSUserDefaults → @AppStorage / SwiftData
- Singletons → swift-dependencies DI
- UIAlertView → .alert() modifier
- MKMapView delegates → SwiftUI Map
- UITableView → List
- UICollectionView → LazyVGrid
- StoreKit 1 → StoreKit 2
- SDWebImage → AsyncImage
- Canvas animations → SwiftUI animations
- Facebook Login → Apple Sign-In
- UIWebView → native SwiftUI Text

### CAN DROP
- Facebook integration (fbOn/Off buttons)
- `testing.png` asset
- iPad storyboard (focus on iPhone first)
- UIWebView-based feed (use native views)
- Canvas framework dependency

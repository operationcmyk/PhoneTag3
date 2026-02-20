"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendTagWarning = exports.nudgePlayers = exports.sendGameInvite = void 0;
const admin = require("firebase-admin");
const functions = require("firebase-functions");
admin.initializeApp();
// ---------------------------------------------------------------------------
// sendGameInvite
//
// Called by the iOS client immediately after a game is created.
// Sends a push notification to every invited player who has an FCM token
// stored under /fcmTokens/{userId}.
//
// Expected payload from client:
// {
//   gameId:          string   — the newly-created game's Firebase key
//   gameTitle:       string   — human-readable game title
//   invitedByName:   string   — display name of the game creator
//   recipientTokens: {        — map of userId -> FCM token
//     [userId: string]: string
//   }
// }
// ---------------------------------------------------------------------------
exports.sendGameInvite = functions.https.onCall(async (data, context) => {
    // Require the caller to be authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in to invite players.");
    }
    const { gameId, gameTitle, invitedByName, recipientTokens } = data;
    if (!gameId || !gameTitle || !invitedByName || !recipientTokens) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields: gameId, gameTitle, invitedByName, recipientTokens");
    }
    const tokens = Object.values(recipientTokens);
    if (tokens.length === 0) {
        return { sent: 0 };
    }
    const message = {
        tokens,
        notification: {
            title: "Phone Tag — You've been invited!",
            body: `${invitedByName} invited you to play "${gameTitle}". Tap to join!`,
        },
        data: {
            type: "game_invite",
            gameId,
            gameTitle,
            invitedByName,
        },
        apns: {
            payload: {
                aps: {
                    // Wake the app in the background to handle the notification
                    "content-available": 1,
                    sound: "default",
                },
            },
        },
        android: {
            priority: "high",
        },
    };
    const response = await admin.messaging().sendEachForMulticast(message);
    // Log any per-token errors (stale tokens, etc.) but don't throw —
    // partial success is acceptable.
    if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
            if (!resp.success) {
                const failedToken = tokens[idx];
                functions.logger.warn("FCM send failed", {
                    token: failedToken,
                    error: resp.error?.message,
                });
            }
        });
    }
    functions.logger.info("sendGameInvite completed", {
        gameId,
        successCount: response.successCount,
        failureCount: response.failureCount,
    });
    return {
        sent: response.successCount,
        failed: response.failureCount,
    };
});
// ---------------------------------------------------------------------------
// nudgePlayers
//
// Called by any player who wants to remind others to take their turn.
// Sends a push notification to every other player in the game.
//
// Expected payload from client:
// {
//   gameId:          string   — the game's Firebase key
//   gameTitle:       string   — human-readable game title
//   nudgedByName:    string   — display name of the player sending the nudge
//   recipientTokens: {        — map of userId -> FCM token (excludes nudger)
//     [userId: string]: string
//   }
// }
// ---------------------------------------------------------------------------
exports.nudgePlayers = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in to nudge players.");
    }
    const { gameId, gameTitle, nudgedByName, recipientTokens } = data;
    if (!gameId || !gameTitle || !nudgedByName || !recipientTokens) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields: gameId, gameTitle, nudgedByName, recipientTokens");
    }
    const tokens = Object.values(recipientTokens);
    if (tokens.length === 0) {
        return { sent: 0 };
    }
    const message = {
        tokens,
        notification: {
            title: "Phone Tag — Your turn!",
            body: `${nudgedByName} is waiting for you in "${gameTitle}". Get out there!`,
        },
        data: {
            type: "nudge",
            gameId,
            gameTitle,
            nudgedByName,
        },
        apns: {
            payload: {
                aps: {
                    "content-available": 1,
                    sound: "default",
                },
            },
        },
        android: {
            priority: "high",
        },
    };
    const response = await admin.messaging().sendEachForMulticast(message);
    if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
            if (!resp.success) {
                functions.logger.warn("FCM nudge send failed", {
                    token: tokens[idx],
                    error: resp.error?.message,
                });
            }
        });
    }
    functions.logger.info("nudgePlayers completed", {
        gameId,
        successCount: response.successCount,
        failureCount: response.failureCount,
    });
    return {
        sent: response.successCount,
        failed: response.failureCount,
    };
});
// ---------------------------------------------------------------------------
// sendTagWarning
//
// Called after a tag is submitted when the guessed location is within 1500ft
// (~457m) of a player's actual location. Warns that player to get moving.
//
// Expected payload from client:
// {
//   recipientToken: string  — FCM token of the player who is close to the tag
//   taggerName:     string  — display name of the player who threw the tag
//   gameTitle:      string  — human-readable game title
// }
// ---------------------------------------------------------------------------
exports.sendTagWarning = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }
    const { recipientToken, taggerName, gameTitle } = data;
    if (!recipientToken || !taggerName || !gameTitle) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields: recipientToken, taggerName, gameTitle");
    }
    const message = {
        token: recipientToken,
        notification: {
            title: "📍 Tag incoming!",
            body: `Someone just dropped a tag near you in "${gameTitle}" — you better get moving!`,
        },
        data: {
            type: "tag_warning",
            taggerName,
            gameTitle,
        },
        apns: {
            payload: {
                aps: {
                    "content-available": 1,
                    sound: "default",
                },
            },
        },
        android: {
            priority: "high",
        },
    };
    try {
        await admin.messaging().send(message);
        functions.logger.info("sendTagWarning sent", { taggerName, gameTitle });
        return { sent: true };
    }
    catch (err) {
        functions.logger.warn("sendTagWarning failed", { error: err });
        return { sent: false };
    }
});
//# sourceMappingURL=index.js.map
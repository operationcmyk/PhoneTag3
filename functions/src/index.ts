import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

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
export const sendGameInvite = functions.https.onCall(async (data, context) => {
  // Require the caller to be authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be signed in to invite players."
    );
  }

  const { gameId, gameTitle, invitedByName, recipientTokens } = data as {
    gameId: string;
    gameTitle: string;
    invitedByName: string;
    recipientTokens: Record<string, string>;
  };

  if (!gameId || !gameTitle || !invitedByName || !recipientTokens) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing required fields: gameId, gameTitle, invitedByName, recipientTokens"
    );
  }

  const tokens = Object.values(recipientTokens);
  if (tokens.length === 0) {
    return { sent: 0 };
  }

  const message: admin.messaging.MulticastMessage = {
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

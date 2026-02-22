import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

admin.initializeApp();

const db = admin.database();

// ---------------------------------------------------------------------------
// sendNotification
//
// Generic push notification dispatcher. Accepts a title, body, data payload,
// and either a single FCM token (for one recipient) or a map of userId→token
// (for multiple recipients). All notification logic lives on the iOS client;
// this function is purely a secure FCM relay.
//
// Expected payload from client:
// {
//   title:           string              — notification title
//   body:            string              — notification body
//   data:            { [key]: string }   — arbitrary key/value data payload
//   token?:          string              — single recipient FCM token
//   tokens?:         { [userId]: string } — map of userId -> FCM token (multicast)
// }
//
// Provide exactly one of `token` (single) or `tokens` (multicast).
// ---------------------------------------------------------------------------
export const sendNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be signed in to send notifications."
    );
  }

  const { title, body, data: notifData, token, tokens } = data as {
    title: string;
    body: string;
    data?: Record<string, string>;
    token?: string;
    tokens?: Record<string, string>;
  };

  if (!title || !body) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing required fields: title, body"
    );
  }

  if (!token && (!tokens || Object.keys(tokens).length === 0)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Provide either 'token' (single recipient) or 'tokens' (multiple recipients)."
    );
  }

  const apns: admin.messaging.ApnsConfig = {
    payload: {
      aps: {
        "content-available": 1,
        sound: "default",
      },
    },
  };

  const android: admin.messaging.AndroidConfig = {
    priority: "high",
  };

  // ── Single recipient ──────────────────────────────────────────────────────
  if (token) {
    const message: admin.messaging.Message = {
      token,
      notification: { title, body },
      data: notifData,
      apns,
      android,
    };

    try {
      await admin.messaging().send(message);
      functions.logger.info("sendNotification (single) sent", { title });
      return { sent: 1, failed: 0 };
    } catch (err) {
      functions.logger.warn("sendNotification (single) failed", { error: err });
      return { sent: 0, failed: 1 };
    }
  }

  // ── Multicast ─────────────────────────────────────────────────────────────
  const tokenList = Object.values(tokens!);
  const message: admin.messaging.MulticastMessage = {
    tokens: tokenList,
    notification: { title, body },
    data: notifData,
    apns,
    android,
  };

  const response = await admin.messaging().sendEachForMulticast(message);

  if (response.failureCount > 0) {
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        functions.logger.warn("sendNotification (multicast) partial failure", {
          token: tokenList[idx],
          error: resp.error?.message,
        });
      }
    });
  }

  functions.logger.info("sendNotification (multicast) completed", {
    title,
    successCount: response.successCount,
    failureCount: response.failureCount,
  });

  return {
    sent: response.successCount,
    failed: response.failureCount,
  };
});

// ---------------------------------------------------------------------------
// enforceNudgeDeadlines  (scheduled — runs every 30 minutes)
//
// Scans all active games for expired nudge deadlines. For each player who
// hasn't logged in (lastUploadedAt < nudgeIssuedAt), deducts one strike and
// sends notifications. Clears nudgeDeadlineAt / nudgeIssuedAt after processing
// so the penalty is applied exactly once per nudge.
// ---------------------------------------------------------------------------
export const enforceNudgeDeadlines = functions.pubsub
  .schedule("every 30 minutes")
  .onRun(async () => {
    const nowMs = Date.now();

    // Fetch all games
    const gamesSnap = await db.ref("games").once("value");
    if (!gamesSnap.exists()) return;

    const gamesData = gamesSnap.val() as Record<string, any>;

    for (const [gameId, game] of Object.entries(gamesData)) {
      // Only process active games with an expired nudge deadline
      if (game.status !== "active") continue;
      if (!game.nudgeDeadlineAt || !game.nudgeIssuedAt) continue;
      if (nowMs < game.nudgeDeadlineAt) continue;

      const nudgeIssuedAt = game.nudgeDeadlineAt as number;

      functions.logger.info(`enforceNudgeDeadlines: processing game ${gameId}`);

      // Clear the deadline first to prevent double-processing across invocations
      await db.ref(`games/${gameId}/nudgeDeadlineAt`).remove();
      await db.ref(`games/${gameId}/nudgeIssuedAt`).remove();

      const players = game.players as Record<string, any> | undefined;
      if (!players) continue;

      for (const [playerId, playerState] of Object.entries(players)) {
        if (!playerState.isActive || playerState.strikes <= 0) continue;

        // Check if they logged in after the nudge was issued
        const locationSnap = await db
          .ref(`locations/${playerId}/lastUploadedAt`)
          .once("value");
        const lastUploadedAt: number = locationSnap.val() ?? 0;

        if (lastUploadedAt >= nudgeIssuedAt) {
          // Player logged in within the window — no penalty
          continue;
        }

        // Deduct a strike using a transaction to avoid races
        const playerRef = db.ref(`games/${gameId}/players/${playerId}`);
        const result = await playerRef.transaction((current: any) => {
          if (!current || !current.isActive || current.strikes <= 0) return current;
          current.strikes = Math.max(0, current.strikes - 1);
          if (current.strikes === 0) current.isActive = false;
          return current;
        });

        if (!result.committed) continue;

        const updatedStrikes = result.snapshot.val()?.strikes ?? 0;
        const wasEliminated = updatedStrikes === 0;

        functions.logger.info(
          `enforceNudgeDeadlines: ${playerId} penalised in ${gameId} (strikes now ${updatedStrikes})`
        );

        // Fetch FCM tokens for notifications
        const allPlayerIds = Object.keys(players);
        const tokenSnap = await db.ref("fcmTokens").once("value");
        const allTokens = tokenSnap.val() as Record<string, string> | null ?? {};

        // Fetch player display name
        const nameSnap = await db.ref(`users/${playerId}/displayName`).once("value");
        const playerName: string = nameSnap.val() ?? "A player";

        // Fetch game title
        const gameTitle: string = game.title ?? "Phone Tag";

        if (wasEliminated) {
          // Notify everyone except the eliminated player
          const recipientTokens = allPlayerIds
            .filter((id) => id !== playerId && allTokens[id])
            .map((id) => allTokens[id]);

          if (recipientTokens.length > 0) {
            await admin.messaging().sendEachForMulticast({
              tokens: recipientTokens,
              notification: {
                title: `☠️ ${playerName} eliminated!`,
                body: `${playerName} didn't log in after a nudge in "${gameTitle}" and has been eliminated.`,
              },
              data: { type: "offline_strike", gameId, gameTitle },
            });
          }
        } else {
          // Notify everyone except the penalised player
          const recipientTokens = allPlayerIds
            .filter((id) => id !== playerId && allTokens[id])
            .map((id) => allTokens[id]);

          if (recipientTokens.length > 0) {
            await admin.messaging().sendEachForMulticast({
              tokens: recipientTokens,
              notification: {
                title: `💀 ${playerName} lost a life!`,
                body: `${playerName} didn't log in within 6 hours of a nudge in "${gameTitle}".`,
              },
              data: { type: "offline_strike", gameId, gameTitle },
            });
          }

          // Also notify the penalised player themselves
          if (allTokens[playerId]) {
            await admin.messaging().send({
              token: allTokens[playerId],
              notification: {
                title: "💥 You lost a life!",
                body: `You didn't log in within 6 hours of a nudge in "${gameTitle}". -1 life.`,
              },
              data: { type: "offline_strike", gameId, gameTitle },
            });
          }
        }

        // Check if only one player remains active — end the game
        const updatedPlayersSnap = await db.ref(`games/${gameId}/players`).once("value");
        const updatedPlayers = updatedPlayersSnap.val() as Record<string, any>;
        const activePlayers = Object.values(updatedPlayers).filter((p: any) => p.isActive);
        if (activePlayers.length <= 1) {
          await db.ref(`games/${gameId}/status`).set("completed");
          await db.ref(`games/${gameId}/endedAt`).set(admin.database.ServerValue.TIMESTAMP);
          functions.logger.info(`enforceNudgeDeadlines: game ${gameId} completed`);
        }
      }
    }
  });

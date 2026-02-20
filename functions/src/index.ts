import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

admin.initializeApp();

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

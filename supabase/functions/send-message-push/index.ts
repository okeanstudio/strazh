import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (
    request.headers.get("x-push-webhook-secret") !==
    Deno.env.get("PUSH_WEBHOOK_SECRET")
  ) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await request.json();
  if (
    payload.type !== "INSERT" ||
    payload.table !== "messages" ||
    !payload.record
  ) {
    return new Response("Ignored", { status: 200 });
  }

  EdgeRuntime.waitUntil(sendPush(payload.record));
  return new Response("OK", { status: 200 });
});

async function sendPush(message: Record<string, unknown>) {
  try {
    const supabase = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );
    const roomId = stringValue(message.room_id);
    const senderId = stringValue(message.profile_id);
    if (!roomId || !senderId) {
      throw new Error("Message is missing room_id or profile_id");
    }

    const [
      { data: participants, error: participantsError },
      { data: room, error: roomError },
    ] = await Promise.all([
      supabase
        .from("room_participants")
        .select("user_id")
        .eq("room_id", roomId),
      supabase
        .from("rooms")
        .select("id")
        .eq("id", roomId)
        .maybeSingle(),
    ]);
    if (participantsError) throw participantsError;
    if (roomError) throw roomError;
    if (!participants || !room) return;

    const recipientIds = participants
      .map((participant) => String(participant.user_id))
      .filter((userId) => userId !== senderId);
    if (recipientIds.length === 0) return;

    const { data: mutedSettings, error: mutedSettingsError } = await supabase
      .from("chat_user_settings")
      .select("user_id")
      .eq("room_id", roomId)
      .eq("is_muted", true)
      .in("user_id", recipientIds);
    if (mutedSettingsError) throw mutedSettingsError;
    const mutedUserIds = new Set(
      mutedSettings?.map((setting) => String(setting.user_id)) ?? [],
    );
    const notifiedRecipientIds = recipientIds.filter(
      (userId) => !mutedUserIds.has(userId),
    );
    if (notifiedRecipientIds.length === 0) return;

    const { data: devices, error: devicesError } = await supabase
      .from("user_devices")
      .select("user_id,fcm_token")
      .in("user_id", notifiedRecipientIds)
      .in("platform", ["mobile", "web"]);
    if (devicesError) throw devicesError;
    const recipientDevices = devices?.filter(
      (device) => String(device.user_id) !== senderId,
    );
    if (!recipientDevices?.length) return;

    const account = JSON.parse(requiredEnv("FIREBASE_SERVICE_ACCOUNT"));
    const accessToken = await getFirebaseAccessToken(account);
    const notificationData = {
      chatId: roomId,
      messageId: stringValue(message.id) ?? "",
      senderName: stringValue(message.sender_name) ?? "Новое сообщение",
      senderId,
      imageUrl: stringValue(message.sender_avatar) ?? "",
    };
    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`;

    await Promise.all(
      recipientDevices.map(async ({ fcm_token: token }) => {
        const response = await fetch(fcmUrl, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              data: notificationData,
              android: { priority: "HIGH" },
              apns: {
                headers: {
                  "apns-push-type": "background",
                  "apns-priority": "5",
                },
                payload: {
                  aps: {
                    "content-available": 1,
                  },
                },
              },
            },
          }),
        });
        if (response.ok) return;

        const details = await response.text();
        throw new Error(`FCM request failed (${response.status}): ${details}`);
      }),
    );
  } catch (error) {
    console.error("Push delivery failed:", error);
  }
}

async function getFirebaseAccessToken(account: {
  client_email: string;
  private_key: string;
  project_id: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value: string | Uint8Array) => {
    const bytes = typeof value === "string"
      ? new TextEncoder().encode(value)
      : value;
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary)
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  };
  const header = encode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = encode(
    JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const pem = account.private_key
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (char) => char.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const unsignedToken = `${header}.${claims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      privateKey,
      new TextEncoder().encode(unsignedToken),
    ),
  );
  const assertion = `${unsignedToken}.${encode(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || typeof result.access_token !== "string") {
    throw new Error(`Firebase OAuth failed (${response.status})`);
  }
  return result.access_token;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

}

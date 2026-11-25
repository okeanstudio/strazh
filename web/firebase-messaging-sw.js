importScripts(
  "https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js",
  "https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js",
);

let messagingReady;

async function initializeMessaging() {
  const configUrl = new URL(
    "firebase-messaging-config.json",
    self.registration.scope,
  );
  const response = await fetch(configUrl);
  if (!response.ok) {
    throw new Error(`Firebase config request failed: ${response.status}`);
  }

  const config = await response.json();
  if (!config.apiKey || !config.appId || !config.vapidKey) {
    throw new Error("Firebase Web App and VAPID config are required");
  }

  firebase.initializeApp(config);
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage(async (payload) => {
    const data = payload.data || {};
    const notification = payload.notification || {};
    await self.registration.showNotification(
      notification.title || data.senderName || "Strazh",
      {
        body: notification.body || "Новое сообщение",
        icon: new URL("icons/Icon-192.png", self.registration.scope).href,
        badge: new URL("icons/Icon-192.png", self.registration.scope).href,
        data: { chatId: data.chatId || "" },
      },
    );
  });
}

messagingReady = initializeMessaging();
messagingReady.catch((error) => {
  console.error("Firebase Messaging worker failed to initialize:", error);
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = new URL(self.registration.scope);
  const chatId = event.notification.data?.chatId;
  if (chatId) targetUrl.searchParams.set("chatId", chatId);
  event.waitUntil(self.clients.openWindow(targetUrl.href));
});

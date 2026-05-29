// Service Worker for Lab Members Background Notifications
const CACHE_NAME = 'lm-cache-v1';

self.addEventListener('install', (e) => {
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(self.clients.claim());
});

// Fetch handler to satisfy PWA requirements silently
self.addEventListener('fetch', (e) => {
  // Pass-through fetches
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});

// Push notification receiver
self.addEventListener('push', (e) => {
  let data = {};
  if (e.data) {
    try {
      data = e.data.json();
    } catch (err) {
      data = { body: e.data.text() };
    }
  }

  const options = {
    body: data.body || 'رسالة جديدة من Lab Members',
    icon: data.icon || 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%2300ff88" stroke-width="2.2"%3E%3Cpath d="M6 3h12M12 3v7M5 21h14M5 21l3.5-10.5h7L19 21"/%3E%3Ccircle cx="12" cy="16" r="2" fill="%2300ff88"/%3E%3C/svg%3E',
    badge: data.badge || 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%2300ff88" stroke-width="2.2"%3E%3Cpath d="M6 3h12M12 3v7M5 21h14M5 21l3.5-10.5h7L19 21"/%3E%3Ccircle cx="12" cy="16" r="2" fill="%2300ff88"/%3E%3C/svg%3E',
    tag: data.tag || 'lm-new-msg',
    renotify: true,
    data: {
      url: data.url || 'chat-prototype_1.html'
    }
  };

  e.waitUntil(
    self.registration.showNotification(data.title || 'Lab Members', options)
  );
});

// Notification click action
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const targetUrl = e.notification.data?.url || 'chat-prototype_1.html';
  
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(targetUrl) && 'focus' in client) {
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});

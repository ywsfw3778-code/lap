const CACHE_NAME = 'lap-chat-v1';

self.addEventListener('install', (e) => {
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (e) => {
  // الأولوية للشبكة دائماً لتفادي أي مشاكل كاش، والرجوع للذاكرة المحلية فقط عند انقطاع الإنترنت
  e.respondWith(
    fetch(e.request).catch(() => {
      return caches.match(e.request);
    })
  );
});

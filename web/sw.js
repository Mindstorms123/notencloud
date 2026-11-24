// Offline-Speicher für die App-Dateien der Notencloud-Web-App.
// VERSION und PRECACHE werden beim Bauen eingesetzt (scripts/web_postbuild.sh).
const VERSION = '__VERSION__';
const PRECACHE = [/*__PRECACHE__*/];
const CACHE = 'notencloud-app-' + VERSION;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Einzeln laden: Eine fehlende Datei darf die Installation nicht verhindern.
    await Promise.all(PRECACHE.map(async (url) => {
      try {
        const response = await fetch(url, { cache: 'reload' });
        if (response.ok) await cache.put(url, response);
      } catch (_) {}
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    // Nur alte App-Fassungen löschen – nicht die heruntergeladenen Noten.
    await Promise.all(names
      .filter((name) => name.startsWith('notencloud-app-') && name !== CACHE)
      .map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

async function fromCache(request) {
  const cache = await caches.open(CACHE);
  return (await cache.match(request)) || (await cache.match(request, { ignoreSearch: true }));
}

async function fromNetwork(request, timeoutMs) {
  const controller = new AbortController();
  const timer = timeoutMs ? setTimeout(() => controller.abort(), timeoutMs) : null;
  try {
    const response = await fetch(request, { signal: controller.signal });
    if (response.ok) {
      const cache = await caches.open(CACHE);
      cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Nextcloud-Proxy und andere fremde Adressen nicht anfassen.
  if (url.origin !== self.location.origin) return;
  if (url.pathname.includes('/__notencloud_scores/')) return;

  if (request.mode === 'navigate') {
    // Startseite: möglichst frisch, ohne Netz (oder bei hängendem Netz) aus dem Speicher.
    event.respondWith((async () => {
      try {
        // Am Zwischenspeicher des Browsers vorbei, damit eine neue Fassung
        // beim nächsten Öffnen sofort da ist.
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 4000);
        try {
          const response = await fetch(request.url, { cache: 'no-store', signal: controller.signal });
          if (response.ok) {
            const cache = await caches.open(CACHE);
            cache.put('./', response.clone()).catch(() => {});
          }
          return response;
        } finally {
          clearTimeout(timer);
        }
      } catch (_) {
        const cache = await caches.open(CACHE);
        return (await cache.match('./')) || (await cache.match('index.html')) || Response.error();
      }
    })());
    return;
  }

  // Übrige App-Dateien: aus dem Speicher, sonst aus dem Netz (und merken).
  event.respondWith((async () => {
    const cached = await fromCache(request);
    if (cached) return cached;
    return fromNetwork(request, 0);
  })());
});

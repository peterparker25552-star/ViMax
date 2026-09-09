/*
 * ViMax service worker.
 *
 * The app is served from the local ViMax engine bridge. Strategy:
 *  - Network-first for pages, API calls, and manifest so sessions and agent
 *    state are always fresh; if the engine is unreachable (phone offline or
 *    app opened after the engine stopped) fall back to the last cached copy
 *    so the installed app still opens.
 *  - Precache the app shell so first paint works without a network.
 *  - Never cache POST/PUT/DELETE requests.
 */

const CACHE = 'vimax-shell-v1';
const SHELL_ASSETS = [
  '/',
  '/index.html',
  '/manifest.webmanifest',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/vimax-dark.svg',
  '/vimax-light.svg',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL_ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Live event stream must always hit the network.
  if (url.pathname === '/api/events') return;

  // Media artifacts can be large; stream them straight from the engine.
  if (url.pathname === '/api/artifact') return;

  if (url.pathname.startsWith('/api/')) {
    event.respondWith(networkFirst(request, {offlineMessage: true}));
    return;
  }

  event.respondWith(networkFirst(request, {}));
});

async function networkFirst(request, {offlineMessage = false} = {}) {
  const cache = await caches.open(CACHE);
  try {
    const response = await fetch(request);
    if (response && response.ok) cache.put(request, response.clone());
    return response;
  } catch (error) {
    const cached = await cache.match(request, {ignoreSearch: request.mode === 'navigate'});
    if (cached) return cached;
    if (request.mode === 'navigate') {
      const shell = await cache.match('/index.html');
      if (shell) return shell;
    }
    if (offlineMessage) {
      return new Response(
        JSON.stringify({error: 'ViMax engine is unreachable. Start the engine, then check the connection in Settings.'}),
        {status: 503, headers: {'Content-Type': 'application/json; charset=utf-8'}}
      );
    }
    return new Response('Offline', {status: 503, statusText: 'Offline'});
  }
}

'use strict';

const CACHE = 'spectrum-strategy-{{BUILD_ID}}';

const SHELL = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'flutter_bootstrap.js',
  'offline-check.html',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);

      await Promise.all(
        SHELL.map((path) =>
          cache.add(new Request(path, { cache: 'reload' })).catch((error) => {
            console.warn('sw: could not precache', path, error);
          })
        )
      );

      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name.startsWith('spectrum-strategy-') && name !== CACHE)
          .map((name) => caches.delete(name))
      );
      await self.clients.claim();

      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        client.postMessage({ type: 'spectrum-update-ready', build: '{{BUILD_ID}}' });
      }
    })()
  );
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data) return;

  if (data.type === 'spectrum-skip-waiting') {
    self.skipWaiting();
    return;
  }

  if (data.type === 'spectrum-cache-these') {
    event.waitUntil(cacheReported(data.urls));
  }
});

async function cacheReported(urls) {
  if (!Array.isArray(urls)) return;
  const cache = await caches.open(CACHE);
  await Promise.all(
    urls.map(async (url) => {
      try {
        const parsed = new URL(url, self.location.origin);
        if (parsed.origin !== self.location.origin) return;
        if (parsed.pathname.startsWith('/__/')) return;
        if (parsed.pathname.endsWith('/version.json')) return;

        const key = parsed.origin + parsed.pathname;
        if (await cache.match(key)) return;

        let response;
        try {
          response = await fetch(key, { cache: 'force-cache' });
        } catch (unsupported) {
          response = await fetch(key);
        }
        if (response.ok && response.type === 'basic') {
          await cache.put(key, response);
        }
      } catch (error) {

      }
    })
  );
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  if (url.origin !== self.location.origin) return;

  if (url.pathname.startsWith('/__/')) return;

  if (url.pathname.endsWith('/version.json')) return;

  if (request.mode === 'navigate') {
    event.respondWith(shellResponse(event, request));
    return;
  }

  event.respondWith(cacheFirst(event, request));
});

async function shellResponse(event, request) {
  const cache = await caches.open(CACHE);

  const exact = await cache.match(request, { ignoreSearch: true });
  if (exact) return exact;
  try {
    const response = await fetch(request);
    if (response.ok && response.type === 'basic') {
      event.waitUntil(cache.put(request, response.clone()));
    }
    return response;
  } catch (error) {
    const cached =
      (await cache.match('index.html')) || (await cache.match('./'));
    if (cached) return cached;
    return new Response(
      'Spectrum Strategy is offline and has not been loaded on this device yet.',
      { status: 503, headers: { 'Content-Type': 'text/plain' } }
    );
  }
}

async function cacheFirst(event, request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;

  const response = await fetch(new Request(request, { cache: 'reload' }));

  if (response.ok && response.type === 'basic') {

    event.waitUntil(cache.put(request, response.clone()));
  }
  return response;
}

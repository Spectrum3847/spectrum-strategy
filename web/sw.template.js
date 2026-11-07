'use strict';

const CACHE = 'spectrum-strategy-{{BUILD_ID}}';

const SHELL = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'flutter_bootstrap.js',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
];

const SUPPORTS_WASM_GC = (() => {
  try {
    return WebAssembly.validate(
      new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0])
    );
  } catch (error) {
    return false;
  }
})();

const IOS_ENGINE = [
  'main.dart.js',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
];

async function precacheOne(cache, path) {
  try {

    const response = await fetch(new Request(path, { cache: 'reload' }));

    if (response.status === 200 && response.type === 'basic') {
      await cache.put(path, response);
    } else {
      console.warn(
        'sw: skipped precaching',
        path,
        'status',
        response.status,
        'type',
        response.type
      );
    }
  } catch (error) {
    console.warn('sw: could not precache', path, error);
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);

      await Promise.all(SHELL.map((path) => precacheOne(cache, path)));
      if (!SUPPORTS_WASM_GC) {
        await Promise.all(IOS_ENGINE.map((path) => precacheOne(cache, path)));
      }

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

function isCacheableGstaticFirebaseSdk(parsed) {
  return (
    parsed.origin === 'https://www.gstatic.com' &&
    parsed.pathname.startsWith('/firebasejs/')
  );
}

async function cacheReported(urls) {
  if (!Array.isArray(urls)) return;
  const cache = await caches.open(CACHE);
  await Promise.all(
    urls.map(async (url) => {
      try {
        const parsed = new URL(url, self.location.origin);
        const sameOrigin = parsed.origin === self.location.origin;
        const gstaticSdk = !sameOrigin && isCacheableGstaticFirebaseSdk(parsed);
        if (!sameOrigin && !gstaticSdk) return;
        if (sameOrigin && parsed.pathname.startsWith('/__/')) return;
        if (sameOrigin && parsed.pathname.endsWith('/version.json')) return;

        const key = sameOrigin ? parsed.origin + parsed.pathname : parsed.toString();
        if (await cache.match(key)) return;

        let response;
        if (gstaticSdk) {

          response = await fetch(key, { mode: 'cors' });
        } else if (SUPPORTS_WASM_GC) {

          try {
            response = await fetch(key, { cache: 'force-cache' });
          } catch (unsupported) {
            response = await fetch(key);
          }
        } else {

          response = await fetch(key, { cache: 'reload' });
        }

        const acceptable =
          response.status === 200 &&
          response.type === (gstaticSdk ? 'cors' : 'basic');
        if (acceptable) {
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

  if (url.origin !== self.location.origin) {

    if (isCacheableGstaticFirebaseSdk(url)) {
      event.respondWith(cacheFirstCors(event, request));
    }
    return;
  }

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

    if (response.status === 200 && response.type === 'basic') {
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

  if (cached && cached.type === 'basic') return cached;

  const response = await fetch(new Request(request, { cache: 'reload' }));

  if (response.status === 200 && response.type === 'basic') {

    event.waitUntil(cache.put(request, response.clone()));
  }
  return response;
}

async function cacheFirstCors(event, request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request);
  if (cached && cached.type === 'cors') return cached;
  const response = await fetch(request);
  if (response.status === 200 && response.type === 'cors') {
    event.waitUntil(cache.put(request, response.clone()));
  }
  return response;
}

const FLUTTER_CACHE_PREFIX = "spectrum-";

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith(FLUTTER_CACHE_PREFIX))
            .map((name) => caches.delete(name)),
        ),
      )
      .catch(() => {

      }),
  );
});

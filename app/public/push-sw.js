function target(url) {
  if (typeof url !== "string" || !url.startsWith("/") || url.startsWith("//")) {
    return "/";
  }
  return url;
}

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {

  }
  const tag =
    typeof data.tag === "string" && data.tag !== "" ? data.tag : undefined;
  event.waitUntil(
    self.registration.showNotification(
      typeof data.title === "string" && data.title !== ""
        ? data.title
        : "Spectrum Strategy",
      {
        body: typeof data.body === "string" ? data.body : "",
        icon: "/icons/Icon-192.png",
        tag,

        renotify: tag !== undefined,
        data: { url: target(data.url) },
      },
    ),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(
    target(event.notification.data?.url),
    self.location.origin,
  );
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({
        type: "window",
        includeUncontrolled: true,
      });
      for (const window of windows) {
        try {
          await window.focus();

          if (new URL(window.url).pathname !== url.pathname)
            await window.navigate(url.href);
          return;
        } catch {

        }
      }
      await self.clients.openWindow(url.href);
    })(),
  );
});

interface Registration {
  unregister(): Promise<boolean>;
}

export interface CacheEnv {
  registrations(): Promise<readonly Registration[]>;
  cacheNames(): Promise<string[]>;
  deleteCache(name: string): Promise<boolean>;
}

export const browserCacheEnv = (): CacheEnv => ({
  registrations: async () =>
    (await navigator.serviceWorker?.getRegistrations()) ?? [],
  cacheNames: async () => (typeof caches === "undefined" ? [] : caches.keys()),
  deleteCache: (name) => caches.delete(name),
});

export async function clearAppCache(env: CacheEnv): Promise<void> {
  const registrations = await env.registrations();
  await Promise.all(registrations.map((r) => r.unregister()));
  const names = await env.cacheNames();
  await Promise.all(names.map((n) => env.deleteCache(n)));
}

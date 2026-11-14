const STUN_ONLY = [
  { urls: ['stun:stun.cloudflare.com:3478'] },
  { urls: ['stun:stun.l.google.com:19302'] },
];
const TURN_TTL_SECONDS = 3600;
const TURN_TIMEOUT_MS = 5_000;

function usableUrl(url) {
  if (typeof url !== 'string') return false;
  const port = /^[a-z]+:(?:\[[^\]]+\]|[^:/?]+)(?::(\d+))?/i.exec(url)?.[1];
  return port !== '53';
}

function filterIceServers(servers) {
  if (!Array.isArray(servers)) return [];
  const kept = [];
  for (const server of servers) {
    const urls = (Array.isArray(server?.urls) ? server.urls : [server?.urls]).filter(usableUrl);
    if (urls.length > 0) kept.push({ ...server, urls });
  }
  return kept;
}

async function iceServers(env, fetchImpl) {
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return STUN_ONLY;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TURN_TIMEOUT_MS);
  try {
    const res = await fetchImpl(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(env.TURN_KEY_ID)}/credentials/generate-ice-servers`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ ttl: TURN_TTL_SECONDS }),
        signal: ctl.signal,
      },
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const servers = filterIceServers((await res.json()).iceServers);
    return servers.length > 0 ? servers : STUN_ONLY;
  } catch (err) {
    console.error('TURN credentials failed:', err && err.message ? err.message : err);
    return STUN_ONLY;
  } finally {
    clearTimeout(timer);
  }
}

export { iceServers, filterIceServers, STUN_ONLY };

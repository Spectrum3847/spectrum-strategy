import { authorizeLead, authorizeRelay } from './chat_auth.mjs';
import { iceServers } from './chat_ice.mjs';
import { createContext } from './context.mjs';
import { corsHeaders, reply } from './cors.mjs';
import { bearerToken } from './id_token.mjs';

const LEAD_ROUTES = { '/chat/relays': 'GET', '/chat/ice': 'GET', '/chat/offer': 'POST' };
const MAX_BODY = 32_768;
const MAX_SDP = 16_384;
const MAX_ID = 128;

function hub(env) {
  return env.CHAT_HUB.get(env.CHAT_HUB.idFromName('hub'));
}

async function handleRelaySocket(request, env) {
  if (request.headers.get('Upgrade') !== 'websocket') {
    return new Response('Expected a WebSocket upgrade', { status: 426 });
  }
  const uid = await authorizeRelay(
    bearerToken(request.headers.get('Authorization')),
    createContext(env),
  );
  if (!uid) return new Response('Unauthorized', { status: 401 });
  return hub(env).fetch(request);
}

async function readOffer(request) {
  const text = await request.text();
  if (text.length > MAX_BODY) return null;
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  const { relayId, sdp } = body ?? {};
  const valid =
    typeof relayId === 'string' &&
    relayId.length >= 1 &&
    relayId.length <= MAX_ID &&
    typeof sdp === 'string' &&
    sdp.length >= 1 &&
    sdp.length <= MAX_SDP;
  return valid ? { relayId, sdp } : null;
}

async function handleLeadRoute(request, env, path) {
  const method = LEAD_ROUTES[path];
  const cors = corsHeaders(request, env, `${method}, OPTIONS`);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== method) return reply({ error: 'method-not-allowed' }, 405, cors);

  const ctx = createContext(env);
  const uid = await authorizeLead(request, ctx);
  if (!uid) return reply({ error: 'unauthorized' }, 401, cors);

  try {
    if (path === '/chat/ice') {
      return reply({ iceServers: await iceServers(env, ctx.fetchImpl) }, 200, cors);
    }
    let forward = request;
    if (path === '/chat/offer') {
      const offer = await readOffer(request);
      if (!offer) return reply({ error: 'bad-request' }, 400, cors);
      forward = new Request(request.url, { method: 'POST', body: JSON.stringify(offer) });
    }
    const res = await hub(env).fetch(forward);
    return reply(await res.json(), res.status, cors);
  } catch (err) {
    console.error('chat hub failed:', err && err.message ? err.message : err);
    return reply({ error: 'failed' }, 502, cors);
  }
}

async function handleChat(request, env) {
  const path = new URL(request.url).pathname;
  if (path !== '/chat/relay' && !(path in LEAD_ROUTES)) {
    return new Response('Not found', { status: 404 });
  }
  if (!env.CHAT_HUB) return reply({ error: 'not-configured' }, 503, {});
  return path === '/chat/relay' ? handleRelaySocket(request, env) : handleLeadRoute(request, env, path);
}

export { handleChat };

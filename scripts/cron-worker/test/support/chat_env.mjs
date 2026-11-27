import { ChatHub } from '../../src/chat_hub.mjs';
import { encodeFields } from '../../src/firestore.mjs';
import { claimedUid } from '../../src/id_token.mjs';

const ORIGIN = 'https://app.example.test';
const NOW = Date.parse('2026-11-12T12:00:00Z');

const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
const idToken = (uid) => `${b64({ alg: 'RS256' })}.${b64({ sub: uid })}.signature`;

class FakeSocket {
  constructor() {
    this.sent = [];
    this.closed = null;
    this.attachment = null;
  }
  send(message) {
    if (this.closed) throw new Error('socket is closed');
    this.sent.push(message);
  }
  close(code, reason) {
    this.closed = { code, reason };
  }
  serializeAttachment(value) {
    this.attachment = structuredClone(value);
  }
  deserializeAttachment() {
    return structuredClone(this.attachment);
  }

  messages() {
    return this.sent.map((m) => JSON.parse(m));
  }
}

function buildChatEnv({ users = {}, relayUids = [], turn, extra = {} } = {}) {
  const calls = [];
  const revoked = new Set();
  const sockets = [];
  const durableCtx = {
    acceptWebSocket: (ws) => sockets.push(ws),
    getWebSockets: () => sockets.filter((ws) => !ws.closed),
    setWebSocketAutoResponse(pair) {
      this.autoResponse = pair;
    },
  };

  const fetchImpl = async (url, init = {}) => {
    const href = String(url);
    calls.push({ url: href, init });
    if (href.startsWith('https://rtc.live.cloudflare.com/')) {
      return turn ? turn(href, init) : new Response('no TURN', { status: 500 });
    }
    const token = String(init.headers?.Authorization ?? '').replace('Bearer ', '');
    const uid = claimedUid(token);
    if (!uid || revoked.has(token) || !(uid in users)) return new Response('{}', { status: 403 });
    const doc = href.split('/documents/')[1];
    if (doc === `userProfiles/${uid}`) {
      return users[uid]
        ? new Response(JSON.stringify({ fields: encodeFields(users[uid]) }), { status: 200 })
        : new Response('{}', { status: 404 });
    }
    if (doc === 'appConfig/relay') {
      return new Response(JSON.stringify({ fields: encodeFields({ uids: relayUids }) }), {
        status: 200,
      });
    }
    return new Response('{}', { status: 404 });
  };

  const env = {
    FIREBASE_PROJECT: 'proj-firebase',
    ALLOWED_ORIGINS: ORIGIN,
    nowMs: NOW,
    fetchImpl,
    runtime: {
      socketPair: () => [new FakeSocket(), new FakeSocket()],
      upgrade: () => new Response('upgraded', { status: 200 }),
      autoResponse: (request, response) => ({ request, response }),
    },
    ...extra,
  };
  const hub = new ChatHub(durableCtx, env);
  env.CHAT_HUB = {
    names: [],
    idFromName(name) {
      this.names.push(name);
      return name;
    },
    get: () => hub,
  };
  return { env, hub, calls, revoked, sockets, durableCtx };
}

const relayRequest = (uid) =>
  new Request('https://worker.test/chat/relay', {
    headers: { Upgrade: 'websocket', Authorization: `Bearer ${idToken(uid)}` },
  });

async function connectRelay(hub, sockets, { uid = 'relay1', ...hello } = {}) {
  await hub.fetch(relayRequest(uid));
  const ws = sockets.at(-1);
  await hub.webSocketMessage(
    ws,
    JSON.stringify({
      type: 'hello',
      relayId: 'r1',
      name: 'Shop relay',
      model: 'model-a',
      build: '20261112',
      busy: false,
      ...hello,
    }),
  );
  return ws;
}

const send = (hub, ws, message) => hub.webSocketMessage(ws, JSON.stringify(message));

const settleMicrotasks = () => new Promise((resolve) => setImmediate(resolve));

export {
  ORIGIN,
  NOW,
  FakeSocket,
  buildChatEnv,
  connectRelay,
  idToken,
  relayRequest,
  send,
  settleMicrotasks,
};

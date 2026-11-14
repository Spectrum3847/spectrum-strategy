import { authorizeRelay } from './chat_auth.mjs';
import { iceServers } from './chat_ice.mjs';
import { createContext } from './context.mjs';
import { bearerToken, claimedUid } from './id_token.mjs';

const AUTH_MS = 60 * 60_000;
const OFFER_TIMEOUT_MS = 20_000;
const MAX_MESSAGE = 32_768;
const MAX_SDP = 16_384;
const MAX_ID = 128;
const MAX_NAME = 64;
const MAX_MODEL = 128;
const MAX_BUILD = 32;

const GONE = { status: 404, error: 'gone' };

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function runtime(env) {
  return (
    env.runtime ?? {
      socketPair: () => Object.values(new WebSocketPair()),
      upgrade: (client) => new Response(null, { status: 101, webSocket: client }),
      autoResponse: (request, response) => new WebSocketRequestResponsePair(request, response),
    }
  );
}

const inRange = (value, min, max) =>
  typeof value === 'string' && value.length >= min && value.length <= max;

function parseHello(msg) {
  if (
    !inRange(msg.relayId, 1, MAX_ID) ||
    !inRange(msg.name, 1, MAX_NAME) ||
    !inRange(msg.model, 0, MAX_MODEL) ||
    !inRange(msg.build, 0, MAX_BUILD) ||
    typeof msg.busy !== 'boolean'
  ) {
    return null;
  }
  const { relayId, name, model, build, busy } = msg;
  return { relayId, name, model, build, busy };
}

class ChatHub {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;

    this.pending = new Map();
    ctx.setWebSocketAutoResponse(runtime(env).autoResponse('ping', 'pong'));
  }

  now() {
    return this.env.nowMs ?? Date.now();
  }

  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === '/chat/relay') return this.accept(request);
    if (path === '/chat/relays') return json({ relays: this.relays() });
    if (path === '/chat/offer') return this.offer(await request.json());
    return new Response('Not found', { status: 404 });
  }

  accept(request) {
    const uid = claimedUid(bearerToken(request.headers.get('Authorization')) ?? '');
    const [client, server] = runtime(this.env).socketPair();
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({
      socketId: crypto.randomUUID(),
      uid,
      authUntil: this.now() + AUTH_MS,
    });
    return runtime(this.env).upgrade(client);
  }

  sockets() {
    const now = this.now();
    const live = [];
    for (const ws of this.ctx.getWebSockets()) {
      const att = ws.deserializeAttachment();
      if (att && att.authUntil > now) live.push({ ws, att });
      else this.close(ws, 1008, 'token expired');
    }
    return live;
  }

  relays() {
    return this.sockets()
      .filter(({ att }) => att.relayId)
      .map(({ att: { relayId, name, model, build, busy } }) => ({
        relayId,
        name,
        model,
        build,
        busy,
      }));
  }

  async offer({ relayId, sdp }) {
    const target = this.sockets().find(({ att }) => att.relayId === relayId);
    if (!target) return json({ error: GONE.error }, GONE.status);
    if (target.att.busy) return json({ error: 'busy' }, 409);

    const servers = await iceServers(this.env, createContext(this.env).fetchImpl);
    const sessionId = crypto.randomUUID();
    const answered = new Promise((resolve) => {
      const timer = setTimeout(
        () => this.settle(sessionId, { status: 504, error: 'timeout' }),
        OFFER_TIMEOUT_MS,
      );
      this.pending.set(sessionId, { socketId: target.att.socketId, timer, resolve });
    });
    try {
      target.ws.send(JSON.stringify({ type: 'offer', sessionId, sdp, iceServers: servers }));
    } catch {
      this.settle(sessionId, GONE);
    }
    const result = await answered;
    return result.sdp ? json({ sdp: result.sdp }) : json({ error: result.error }, result.status);
  }

  settle(sessionId, result) {
    const waiting = this.pending.get(sessionId);
    if (!waiting) return;
    clearTimeout(waiting.timer);
    this.pending.delete(sessionId);
    waiting.resolve(result);
  }

  close(ws, code, reason) {
    const att = ws.deserializeAttachment();
    for (const [sessionId, waiting] of this.pending) {
      if (waiting.socketId === att?.socketId) this.settle(sessionId, GONE);
    }
    try {
      ws.close(code, reason);
    } catch {

    }
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== 'string' || message.length > MAX_MESSAGE) return;
    let msg;
    try {
      msg = JSON.parse(message);
    } catch {
      return;
    }
    if (!msg || typeof msg !== 'object') return;
    const att = ws.deserializeAttachment();
    if (!att || att.authUntil <= this.now()) return this.close(ws, 1008, 'token expired');

    if (msg.type === 'hello') {
      const hello = parseHello(msg);
      if (!hello) return this.close(ws, 1008, 'bad hello');
      for (const other of this.ctx.getWebSockets()) {
        const theirs = other.deserializeAttachment();
        if (theirs?.relayId === hello.relayId && theirs.socketId !== att.socketId) {
          this.close(other, 1000, 'replaced');
        }
      }
      ws.serializeAttachment({ ...att, ...hello });
    } else if (msg.type === 'busy' && typeof msg.busy === 'boolean') {
      ws.serializeAttachment({ ...att, busy: msg.busy });
    } else if (msg.type === 'token') {
      const uid = await authorizeRelay(msg.token, createContext(this.env));
      if (!uid || uid !== att.uid) return this.close(ws, 1008, 'unauthorized');
      ws.serializeAttachment({ ...ws.deserializeAttachment(), authUntil: this.now() + AUTH_MS });
    } else if (msg.type === 'answer' || msg.type === 'reject') {
      this.answered(msg, att);
    }
  }

  answered(msg, att) {
    if (this.pending.get(msg.sessionId)?.socketId !== att.socketId) return;
    if (msg.type === 'answer' && inRange(msg.sdp, 1, MAX_SDP)) {
      this.settle(msg.sessionId, { sdp: msg.sdp });
      return;
    }
    const message = msg.type === 'reject' && inRange(msg.message, 1, 256) ? msg.message : 'relay error';
    this.settle(msg.sessionId, { status: 502, error: message });
  }

  async webSocketClose(ws) {
    this.close(ws, 1000, 'closed');
  }

  async webSocketError(ws) {
    this.close(ws, 1011, 'error');
  }
}

export { ChatHub, OFFER_TIMEOUT_MS, AUTH_MS };

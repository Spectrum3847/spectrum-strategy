import { test } from 'node:test';
import assert from 'node:assert/strict';

import worker from '../src/index.mjs';
import {
  ORIGIN,
  buildChatEnv,
  connectRelay,
  idToken,
  send,
  settleMicrotasks,
} from './support/chat_env.mjs';

const USERS = {
  relay1: { roles: ['scouter'] },
  lead1: { roles: ['strategy'] },
  scout1: { roles: ['scouter'] },
};

const setup = (options = {}) => buildChatEnv({ users: USERS, relayUids: ['relay1'], ...options });

const call = (path, { method = 'GET', token, origin = ORIGIN, body, headers = {} } = {}) =>
  new Request(`https://worker.test${path}`, {
    method,
    headers: {
      ...(origin ? { Origin: origin } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    ...(body === undefined ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
  });

const LEAD = idToken('lead1');

test('every lead route needs a signed-in member with a lead role', async () => {
  const { env } = setup();
  for (const [path, method] of [
    ['/chat/relays', 'GET'],
    ['/chat/ice', 'GET'],
    ['/chat/offer', 'POST'],
  ]) {
    const body = method === 'POST' ? { relayId: 'r1', sdp: 'v=0' } : undefined;
    for (const token of [undefined, 'junk', idToken('scout1'), idToken('stranger')]) {
      const res = await worker.fetch(call(path, { method, token, body }), env);
      assert.equal(res.status, 401, `${path} ${String(token).slice(0, 12)}`);
      assert.deepEqual(await res.json(), { error: 'unauthorized' });
    }
  }
});

test('the preflight answers without a token and allows the route method', async () => {
  const { env, calls } = setup();
  const offer = await worker.fetch(call('/chat/offer', { method: 'OPTIONS' }), env);
  assert.equal(offer.status, 204);
  assert.equal(offer.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  assert.equal(offer.headers.get('Access-Control-Allow-Methods'), 'POST, OPTIONS');
  assert.match(offer.headers.get('Access-Control-Allow-Headers'), /Authorization/);
  assert.match(offer.headers.get('Access-Control-Allow-Headers'), /Content-Type/);

  const relays = await worker.fetch(call('/chat/relays', { method: 'OPTIONS' }), env);
  assert.equal(relays.headers.get('Access-Control-Allow-Methods'), 'GET, OPTIONS');
  assert.equal(calls.length, 0);
});

test('responses allow the app origin and refuse others', async () => {
  const { env } = setup();
  const allowed = await worker.fetch(call('/chat/relays', { token: LEAD }), env);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  const other = await worker.fetch(
    call('/chat/relays', { token: LEAD, origin: 'https://evil.example' }),
    env,
  );
  assert.equal(other.headers.get('Access-Control-Allow-Origin'), null);
  const denied = await worker.fetch(call('/chat/relays', {}), env);
  assert.equal(denied.headers.get('Access-Control-Allow-Origin'), ORIGIN);
});

test('a wrong method is 405 and an unknown chat path is 404', async () => {
  const { env } = setup();
  assert.equal((await worker.fetch(call('/chat/relays', { method: 'POST', token: LEAD }), env)).status, 405);
  assert.equal((await worker.fetch(call('/chat/offer', { method: 'GET', token: LEAD }), env)).status, 405);
  assert.equal((await worker.fetch(call('/chat/other', { token: LEAD }), env)).status, 404);
});

test('the Worker answers 503 when the hub binding is missing', async () => {
  const { env } = setup();
  delete env.CHAT_HUB;
  assert.equal((await worker.fetch(call('/chat/relays', { token: LEAD }), env)).status, 503);
});

test('GET /chat/relays lists the connected relays through the single hub instance', async () => {
  const { env, hub, sockets } = setup();
  await connectRelay(hub, sockets);
  const res = await worker.fetch(call('/chat/relays', { token: LEAD }), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {
    relays: [{ relayId: 'r1', name: 'Shop relay', model: 'model-a', build: '20261112', busy: false }],
  });
  assert.deepEqual(env.CHAT_HUB.names, ['hub']);
});

test('GET /chat/ice answers STUN only without the TURN secrets', async () => {
  const { env } = setup();
  const res = await worker.fetch(call('/chat/ice', { token: LEAD }), env);
  assert.equal(res.status, 200);
  const { iceServers } = await res.json();
  assert.deepEqual(
    iceServers.flatMap((s) => s.urls),
    ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'],
  );
});

test('POST /chat/offer returns the relay answer', async () => {
  const { env, hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  const reply = worker.fetch(
    call('/chat/offer', { method: 'POST', token: LEAD, body: { relayId: 'r1', sdp: 'offer-sdp' } }),
    env,
  );
  await settleMicrotasks();
  const [offer] = ws.messages();
  assert.equal(offer.sdp, 'offer-sdp');
  await send(hub, ws, { type: 'answer', sessionId: offer.sessionId, sdp: 'answer-sdp' });
  const res = await reply;
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  assert.deepEqual(await res.json(), { sdp: 'answer-sdp' });
});

test('POST /chat/offer passes the hub status codes through', async () => {
  const { env, hub, sockets } = setup();
  const gone = await worker.fetch(
    call('/chat/offer', { method: 'POST', token: LEAD, body: { relayId: 'nope', sdp: 'v=0' } }),
    env,
  );
  assert.equal(gone.status, 404);
  assert.deepEqual(await gone.json(), { error: 'gone' });

  await connectRelay(hub, sockets, { busy: true });
  const busy = await worker.fetch(
    call('/chat/offer', { method: 'POST', token: LEAD, body: { relayId: 'r1', sdp: 'v=0' } }),
    env,
  );
  assert.equal(busy.status, 409);
});

test('POST /chat/offer refuses a bad body before the hub sees it', async () => {
  const { env, hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  const bodies = [
    'not json',
    'null',
    {},
    { relayId: 'r1' },
    { sdp: 'v=0' },
    { relayId: '', sdp: 'v=0' },
    { relayId: 'x'.repeat(129), sdp: 'v=0' },
    { relayId: 'r1', sdp: '' },
    { relayId: 'r1', sdp: 'x'.repeat(16385) },
    { relayId: 5, sdp: 'v=0' },
    { relayId: 'r1', sdp: 'x'.repeat(40_000) },
  ];
  for (const body of bodies) {
    const res = await worker.fetch(call('/chat/offer', { method: 'POST', token: LEAD, body }), env);
    assert.equal(res.status, 400, JSON.stringify(body)?.slice(0, 40));
  }
  const edge = await worker.fetch(
    call('/chat/offer', {
      method: 'POST',
      token: LEAD,
      body: { relayId: 'x'.repeat(128), sdp: 'x'.repeat(16384) },
    }),
    env,
  );
  assert.equal(edge.status, 404, 'the limits themselves are accepted');
  assert.deepEqual(ws.sent, []);
});

test('a hub failure is 502', async () => {
  const { env } = setup();
  env.CHAT_HUB.get = () => ({
    fetch: async () => {
      throw new Error('overloaded');
    },
  });
  const quiet = console.error;
  console.error = () => {};
  try {
    const res = await worker.fetch(call('/chat/relays', { token: LEAD }), env);
    assert.equal(res.status, 502);
  } finally {
    console.error = quiet;
  }
});

const upgrade = (token) =>
  call('/chat/relay', { token, origin: null, headers: { Upgrade: 'websocket' } });

test('the relay socket needs an upgrade request and a relay token', async () => {
  const { env } = setup();
  assert.equal((await worker.fetch(call('/chat/relay', { token: idToken('relay1') }), env)).status, 426);
  for (const token of [undefined, 'junk', LEAD, idToken('scout1'), idToken('stranger')]) {
    const res = await worker.fetch(upgrade(token), env);
    assert.equal(res.status, 401, String(token).slice(0, 12));
  }
});

test('a listed relay account gets its socket accepted by the hub', async () => {
  const { env, sockets } = setup();
  const res = await worker.fetch(upgrade(idToken('relay1')), env);
  assert.equal(res.status, 200);
  assert.equal(sockets.length, 1);
  assert.equal(sockets[0].deserializeAttachment().uid, 'relay1');
  assert.deepEqual(env.CHAT_HUB.names, ['hub']);
});

test('the chat routes do not accept the scheduler token', async () => {
  const { env } = setup();
  env.RUN_TOKEN = 'run-token';
  const res = await worker.fetch(
    call('/chat/relays', { headers: { 'X-Run-Token': 'run-token' } }),
    env,
  );
  assert.equal(res.status, 401);
});

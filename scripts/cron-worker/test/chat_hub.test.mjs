import { test, mock } from 'node:test';
import assert from 'node:assert/strict';

import { AUTH_MS, OFFER_TIMEOUT_MS } from '../src/chat_hub.mjs';
import { STUN_ONLY } from '../src/chat_ice.mjs';
import {
  buildChatEnv,
  connectRelay,
  idToken,
  relayRequest,
  send,
  settleMicrotasks,
} from './support/chat_env.mjs';

const USERS = {
  relay1: { roles: ['scouter'] },
  relay2: { roles: ['scouter'] },
  lead1: { roles: ['strategy'] },
};

const setup = (options = {}) =>
  buildChatEnv({ users: USERS, relayUids: ['relay1', 'relay2'], ...options });

const offerRequest = (body) =>
  new Request('https://hub/chat/offer', { method: 'POST', body: JSON.stringify(body) });
const listRelays = async (hub) =>
  (await hub.fetch(new Request('https://hub/chat/relays'))).json();

test('the hub answers the relay keepalive without waking', () => {
  const { durableCtx } = setup();
  assert.deepEqual(durableCtx.autoResponse, { request: 'ping', response: 'pong' });
});

test('a relay shows in the list after hello, with its details and busy flag', async () => {
  const { hub, sockets } = setup();
  assert.deepEqual(await listRelays(hub), { relays: [] });

  await hub.fetch(relayRequest('relay1'));
  assert.deepEqual(await listRelays(hub), { relays: [] }, 'not listed before hello');

  await send(hub, sockets[0], {
    type: 'hello',
    relayId: 'r1',
    name: 'Shop relay',
    model: 'model-a',
    build: '20261112',
    busy: false,
  });
  assert.deepEqual(await listRelays(hub), {
    relays: [
      { relayId: 'r1', name: 'Shop relay', model: 'model-a', build: '20261112', busy: false },
    ],
  });

  await send(hub, sockets[0], { type: 'busy', busy: true });
  assert.equal((await listRelays(hub)).relays[0].busy, true);
  await send(hub, sockets[0], { type: 'busy', busy: 'yes' });
  assert.equal((await listRelays(hub)).relays[0].busy, true, 'a bad flag changes nothing');
});

test('a hello over the limits closes the socket', async () => {
  const bad = [
    { relayId: '' },
    { relayId: 'x'.repeat(129) },
    { name: '' },
    { name: 'n'.repeat(65) },
    { model: 'm'.repeat(129) },
    { build: 'b'.repeat(33) },
    { busy: 'no' },
  ];
  for (const change of bad) {
    const { hub, sockets } = setup();
    const ws = await connectRelay(hub, sockets, change);
    assert.equal(ws.closed?.code, 1008, JSON.stringify(change).slice(0, 40));
    assert.deepEqual(await listRelays(hub), { relays: [] });
  }
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets, { name: 'n'.repeat(64), model: '', build: '' });
  assert.equal(ws.closed, null);
});

test('a second socket with the same relayId replaces the first', async () => {
  const { hub, sockets } = setup();
  const first = await connectRelay(hub, sockets, { name: 'old' });
  const second = await connectRelay(hub, sockets, { name: 'new' });
  assert.equal(first.closed.reason, 'replaced');
  assert.equal(second.closed, null);
  assert.deepEqual(
    (await listRelays(hub)).relays.map((r) => r.name),
    ['new'],
  );
});

test('a socket past its auth time is closed and never listed or offered', async () => {
  const { env, hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  env.nowMs += AUTH_MS;
  assert.deepEqual(await listRelays(hub), { relays: [] });
  assert.equal(ws.closed.code, 1008);

  const offered = await hub.fetch(offerRequest({ relayId: 'r1', sdp: 'v=0' }));
  assert.equal(offered.status, 404);
  assert.deepEqual(ws.sent, []);
});

test('a token refresh from the same relay account extends the auth time', async () => {
  const { env, hub, sockets, calls } = setup();
  const ws = await connectRelay(hub, sockets);
  env.nowMs += 45 * 60_000;
  await send(hub, ws, { type: 'token', token: idToken('relay1') });
  assert.match(calls.at(-1).url, /appConfig\/relay$/);

  env.nowMs += 30 * 60_000;
  assert.equal((await listRelays(hub)).relays.length, 1, 'past the first hour, inside the second');
  assert.equal(ws.closed, null);

  env.nowMs += AUTH_MS;
  assert.deepEqual(await listRelays(hub), { relays: [] });
});

test('a refused, revoked or foreign token closes the socket', async () => {
  for (const token of [idToken('lead1'), idToken('relay2'), 'junk', undefined]) {
    const { hub, sockets } = setup({ relayUids: ['relay1', 'relay2'] });
    const ws = await connectRelay(hub, sockets);
    await send(hub, ws, { type: 'token', token });
    assert.equal(ws.closed?.code, 1008, String(token).slice(0, 20));
  }
  const { hub, sockets, revoked } = setup();
  const ws = await connectRelay(hub, sockets);
  revoked.add(idToken('relay1'));
  await send(hub, ws, { type: 'token', token: idToken('relay1') });
  assert.equal(ws.closed.code, 1008);
});

test('an offer is forwarded to the relay with ICE servers, and its answer comes back', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);

  const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
  await settleMicrotasks();
  const [offer] = ws.messages();
  assert.equal(offer.type, 'offer');
  assert.equal(offer.sdp, 'offer-sdp');
  assert.match(offer.sessionId, /^[0-9a-f-]{36}$/);
  assert.deepEqual(offer.iceServers, STUN_ONLY);

  await send(hub, ws, { type: 'answer', sessionId: offer.sessionId, sdp: 'answer-sdp' });
  const res = await reply;
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { sdp: 'answer-sdp' });
});

test('a reject comes back as 502 with its message', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
  await settleMicrotasks();
  const [offer] = ws.messages();
  await send(hub, ws, { type: 'reject', sessionId: offer.sessionId, message: 'already serving 4 chats' });
  const res = await reply;
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { error: 'already serving 4 chats' });
});

test('an offer to a relay that is not there is 404, and to a busy relay 409', async () => {
  const { hub, sockets } = setup();
  const missing = await hub.fetch(offerRequest({ relayId: 'nope', sdp: 'v=0' }));
  assert.equal(missing.status, 404);
  assert.deepEqual(await missing.json(), { error: 'gone' });

  const ws = await connectRelay(hub, sockets, { busy: true });
  const busy = await hub.fetch(offerRequest({ relayId: 'r1', sdp: 'v=0' }));
  assert.equal(busy.status, 409);
  assert.deepEqual(await busy.json(), { error: 'busy' });
  assert.deepEqual(ws.sent, []);
});

test('an answer from another socket, or for an unknown session, does not settle an offer', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets, { relayId: 'r1' });
  const other = await connectRelay(hub, sockets, { relayId: 'r2', uid: 'relay2' });

  const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
  await settleMicrotasks();
  const [offer] = ws.messages();
  assert.deepEqual(other.sent, []);

  await send(hub, other, { type: 'answer', sessionId: offer.sessionId, sdp: 'forged' });
  await send(hub, ws, { type: 'answer', sessionId: 'unknown', sdp: 'stray' });
  await send(hub, ws, { type: 'answer', sessionId: offer.sessionId, sdp: 'real' });
  assert.deepEqual(await (await reply).json(), { sdp: 'real' });
});

test('an answer without a usable SDP is a relay error', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
  await settleMicrotasks();
  const [offer] = ws.messages();
  await send(hub, ws, { type: 'answer', sessionId: offer.sessionId, sdp: 'x'.repeat(16385) });
  const res = await reply;
  assert.equal(res.status, 502);
});

test('a relay that never answers gets 504 after 20 seconds', async () => {
  mock.timers.enable({ apis: ['setTimeout'] });
  try {
    const { hub, sockets } = setup();
    const ws = await connectRelay(hub, sockets);
    const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
    await settleMicrotasks();
    mock.timers.tick(OFFER_TIMEOUT_MS - 1);
    await settleMicrotasks();
    assert.equal(OFFER_TIMEOUT_MS, 20_000);
    mock.timers.tick(1);
    const res = await reply;
    assert.equal(res.status, 504);
    assert.deepEqual(await res.json(), { error: 'timeout' });

    const [offer] = ws.messages();
    await send(hub, ws, { type: 'answer', sessionId: offer.sessionId, sdp: 'late' });
  } finally {
    mock.timers.reset();
  }
});

test('a relay that disconnects mid-offer makes the offer 404', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
  await settleMicrotasks();
  await hub.webSocketClose(ws, 1006, '', false);
  const res = await reply;
  assert.equal(res.status, 404);
  assert.deepEqual(await res.json(), { error: 'gone' });
});

test('a socket that cannot be written to makes the offer 404', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  ws.send = () => {
    throw new Error('socket is closed');
  };
  const res = await hub.fetch(offerRequest({ relayId: 'r1', sdp: 'v=0' }));
  assert.equal(res.status, 404);
});

test('with TURN configured the relay gets the same filtered list a browser does', async () => {
  const turn = async () =>
    new Response(
      JSON.stringify({
        iceServers: [
          {
            urls: ['turn:turn.example:3478?transport=udp', 'turn:turn.example:53?transport=udp'],
            username: 'u',
            credential: 'c',
          },
        ],
      }),
      { status: 200 },
    );
  const { hub, sockets } = setup({
    turn,
    extra: { TURN_KEY_ID: 'k', TURN_KEY_API_TOKEN: 't' },
  });
  const ws = await connectRelay(hub, sockets);
  const reply = hub.fetch(offerRequest({ relayId: 'r1', sdp: 'offer-sdp' }));
  await settleMicrotasks();
  const [offer] = ws.messages();
  assert.deepEqual(offer.iceServers, [
    { urls: ['turn:turn.example:3478?transport=udp'], username: 'u', credential: 'c' },
  ]);
  await send(hub, ws, { type: 'answer', sessionId: offer.sessionId, sdp: 'a' });
  await reply;
});

test('junk messages are ignored', async () => {
  const { hub, sockets } = setup();
  const ws = await connectRelay(hub, sockets);
  await hub.webSocketMessage(ws, 'not json');
  await hub.webSocketMessage(ws, 'null');
  await hub.webSocketMessage(ws, new ArrayBuffer(4));
  await hub.webSocketMessage(ws, JSON.stringify({ type: 'unknown' }));
  assert.equal(ws.closed, null);
  assert.equal((await listRelays(hub)).relays.length, 1);
});

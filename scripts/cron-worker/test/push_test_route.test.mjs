import { test } from 'node:test';
import assert from 'node:assert/strict';

import worker from '../src/index.mjs';
import { buildPushEnv, fcm, readPush, subscriptionDoc } from './support/push_env.mjs';

const ORIGIN = 'https://app.example.test';

const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
const idToken = (uid) => `${b64({ alg: 'RS256' })}.${b64({ sub: uid })}.signature`;

const request = (token, { method = 'POST', origin = ORIGIN } = {}) =>
  new Request('https://worker.test/push/test', {
    method,
    headers: {
      Origin: origin,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });

async function setup(overrides = {}) {
  return buildPushEnv({
    subscriptions: {
      s1: await subscriptionDoc('u1', fcm('u1-phone')),
      s2: await subscriptionDoc('u1', fcm('u1-laptop')),
      s3: await subscriptionDoc('u2', fcm('u2-phone')),
    },
    ...overrides,
  });
}

test('a signed-in user gets a test push on their own devices only', async () => {
  const { env, pushes, profileReads } = await setup();
  const token = idToken('u1');
  const res = await worker.fetch(request(token), env);

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, sent: 2, gone: 0, failed: 0 });
  assert.deepEqual(pushes.map((p) => p.url).sort(), [fcm('u1-laptop'), fcm('u1-phone')]);

  assert.deepEqual(profileReads, [{ uid: 'u1', authorization: `Bearer ${token}` }]);

  const message = await readPush(pushes[0].url, pushes[0].init.body);
  assert.match(message.title, /Shift reminders are on/);
  assert.equal(message.url, '/settings?s=device');
  assert.match(message.tag, /^test-/);
  assert.equal(pushes[0].init.headers.TTL, '120');
});

test('the response allows the app origin and refuses others', async () => {
  const { env } = await setup();
  const allowed = await worker.fetch(request(idToken('u1')), env);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), ORIGIN);

  const other = await worker.fetch(request(idToken('u1'), { origin: 'https://evil.example' }), env);
  assert.equal(other.headers.get('Access-Control-Allow-Origin'), null);
});

test('the preflight answers without a token', async () => {
  const { env } = await setup();
  const res = await worker.fetch(request(null, { method: 'OPTIONS' }), env);
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  assert.match(res.headers.get('Access-Control-Allow-Headers'), /Authorization/);
});

test('no token, a malformed token or a token Firestore refuses is 401 and sends nothing', async () => {
  const { env, pushes } = await setup({ profiles: { u1: 401 } });
  assert.equal((await worker.fetch(request(null), env)).status, 401);
  assert.equal((await worker.fetch(request('not-a-token'), env)).status, 401);
  assert.equal((await worker.fetch(request(idToken('u1')), env)).status, 401);
  assert.equal(pushes.length, 0);
});

test('only POST is allowed', async () => {
  const { env } = await setup();
  assert.equal((await worker.fetch(request(idToken('u1'), { method: 'GET' }), env)).status, 405);
});

test('a user with no saved device gets 404', async () => {
  const { env, pushes } = await setup();
  const res = await worker.fetch(request(idToken('u9')), env);
  assert.equal(res.status, 404);
  assert.deepEqual(await res.json(), { ok: false, error: 'no-subscription' });
  assert.equal(pushes.length, 0);
});

test('an expired subscription is deleted and reported as gone', async () => {
  const { env, store } = await setup({ pushStatus: { [fcm('u1-phone')]: 410 } });
  const res = await worker.fetch(request(idToken('u1')), env);
  assert.deepEqual(await res.json(), { ok: true, sent: 1, gone: 1, failed: 0 });
  assert.equal(store.pushSubscriptions.s1, undefined);
  assert.ok(store.pushSubscriptions.s2);
  assert.ok(store.pushSubscriptions.s3);
});

test('when every device is gone the test reports that it reached none', async () => {
  const { env } = await setup({
    pushStatus: { [fcm('u1-phone')]: 410, [fcm('u1-laptop')]: 410 },
  });
  const res = await worker.fetch(request(idToken('u1')), env);
  assert.deepEqual(await res.json(), { ok: false, sent: 0, gone: 2, failed: 0 });
});

test('without the VAPID secrets the route says push is not set up', async () => {
  const { env } = await setup({ vapid: false });
  const res = await worker.fetch(request(idToken('u1')), env);
  assert.equal(res.status, 503);
});

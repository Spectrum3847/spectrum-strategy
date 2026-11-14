import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  b64urlDecode,
  b64urlEncode,
  createVapid,
  encryptPayload,
  isAllowedPushEndpoint,
  sendWebPush,
} from '../src/webpush.mjs';

const RFC = {
  plaintext: 'When I grow up, I want to be a watermelon',
  authSecret: 'BTBZMqHH6r4Tts7J_aSIgg',
  uaPublic:
    'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  asPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  asPublic:
    'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  body:
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml' +
    'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT' +
    'pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};

async function rfcSenderKey() {
  const publicRaw = b64urlDecode(RFC.asPublic);
  const privateKey = await crypto.subtle.importKey(
    'jwk',
    {
      kty: 'EC',
      crv: 'P-256',
      d: RFC.asPrivate,
      x: b64urlEncode(publicRaw.slice(1, 33)),
      y: b64urlEncode(publicRaw.slice(33, 65)),
    },
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    ['deriveBits'],
  );
  return { privateKey, publicRaw };
}

async function newSubscription(endpoint = 'https://fcm.googleapis.com/fcm/send/abc') {
  const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, [
    'deriveBits',
  ]);
  const p256dh = b64urlEncode(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
  const auth = b64urlEncode(crypto.getRandomValues(new Uint8Array(16)));
  return { endpoint, p256dh, auth, privateKey: pair.privateKey };
}

async function newVapid(subject = 'mailto:push@example.test') {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
  const publicKey = b64urlEncode(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
  const privateKey = (await crypto.subtle.exportKey('jwk', pair.privateKey)).d;
  return { vapid: createVapid({ publicKey, privateKey, subject }), publicKey, verifyKey: pair.publicKey };
}

test('encryption reproduces the RFC 8291 test vector byte for byte', async () => {
  const body = await encryptPayload(
    new TextEncoder().encode(RFC.plaintext),
    { p256dh: RFC.uaPublic, auth: RFC.authSecret },
    { salt: b64urlDecode(RFC.salt), senderKey: await rfcSenderKey() },
  );
  assert.equal(b64urlEncode(body), RFC.body);

  assert.equal(body.length, 86 + RFC.plaintext.length + 1 + 16);
});

test('a random sender key and salt give a different body each time', async () => {
  const sub = await newSubscription();
  const plaintext = new TextEncoder().encode('hello');
  const a = await encryptPayload(plaintext, sub);
  const b = await encryptPayload(plaintext, sub);
  assert.notDeepEqual(a, b);

  assert.equal(new DataView(a.buffer).getUint32(16), 4096);
  assert.equal(a[20], 65);
  assert.equal(a.length, 86 + plaintext.length + 1 + 16);
});

test('encryption refuses keys of the wrong size', async () => {
  const sub = await newSubscription();
  const text = new TextEncoder().encode('x');
  await assert.rejects(encryptPayload(text, { ...sub, auth: 'AAAA' }));
  await assert.rejects(encryptPayload(text, { ...sub, p256dh: 'AAAA' }));
});

test('the VAPID header carries a token the public key verifies, scoped to the push service', async () => {
  const { vapid, publicKey, verifyKey } = await newVapid();
  const now = Date.parse('2026-11-10T18:00:00Z');
  const header = await vapid.authorization('https://fcm.googleapis.com', now);

  const match = /^vapid t=([\w-]+)\.([\w-]+)\.([\w-]+), k=([\w-]+)$/.exec(header);
  assert.ok(match, header);
  assert.equal(match[4], publicKey);
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(match[2])));
  assert.equal(claims.aud, 'https://fcm.googleapis.com');
  assert.equal(claims.sub, 'mailto:push@example.test');
  assert.ok(claims.exp > now / 1000 && claims.exp - now / 1000 <= 24 * 60 * 60);
  assert.deepEqual(JSON.parse(new TextDecoder().decode(b64urlDecode(match[1]))), {
    typ: 'JWT',
    alg: 'ES256',
  });

  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    verifyKey,
    b64urlDecode(match[3]),
    new TextEncoder().encode(`${match[1]}.${match[2]}`),
  );
  assert.equal(valid, true);
});

test('only the real push services are allowed as endpoints', () => {
  for (const ok of [
    'https://fcm.googleapis.com/fcm/send/abc',
    'https://updates.push.services.mozilla.com/wpush/v2/abc',
    'https://web.push.apple.com/abc',
    'https://par02p.notify.windows.com/w/?token=abc',
  ]) {
    assert.equal(isAllowedPushEndpoint(ok), true, ok);
  }
  for (const bad of [
    'http://fcm.googleapis.com/fcm/send/abc',
    'https://evil.example/fcm.googleapis.com',
    'https://fcm.googleapis.com.evil.example/x',
    'https://169.254.169.254/latest',
    'not a url',
  ]) {
    assert.equal(isAllowedPushEndpoint(bad), false, bad);
  }
});

function pushFetch(status, calls = []) {
  return async (url, init) => {
    calls.push({ url, init });
    return new Response(null, { status });
  };
}

test('sendWebPush posts an encrypted body with VAPID and the push headers', async () => {
  const sub = await newSubscription();
  const { vapid } = await newVapid();
  const calls = [];
  const result = await sendWebPush({
    fetchImpl: pushFetch(201, calls),
    vapid,
    subscription: sub,
    payload: { title: 'Hi' },
    nowMs: Date.parse('2026-11-10T18:00:00Z'),
    ttl: 90,
  });
  assert.deepEqual(result, { outcome: 'sent', status: 201 });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, sub.endpoint);
  const { method, headers, body } = calls[0].init;
  assert.equal(method, 'POST');
  assert.equal(headers['Content-Encoding'], 'aes128gcm');
  assert.equal(headers.TTL, '90');
  assert.match(headers.Authorization, /^vapid t=/);
  assert.ok(body.length > 86);
});

test('push responses map to sent, gone, retry and rejected', async () => {
  const sub = await newSubscription();
  const { vapid } = await newVapid();
  const run = (fetchImpl) =>
    sendWebPush({ fetchImpl, vapid, subscription: sub, payload: {}, nowMs: 0 });

  assert.equal((await run(pushFetch(404))).outcome, 'gone');
  assert.equal((await run(pushFetch(410))).outcome, 'gone');
  assert.equal((await run(pushFetch(429))).outcome, 'retry');
  assert.equal((await run(pushFetch(503))).outcome, 'retry');
  assert.equal((await run(pushFetch(403))).outcome, 'rejected');
  assert.equal((await run(pushFetch(302))).outcome, 'rejected');
  assert.equal(
    (
      await run(async () => {
        throw new Error('network down');
      })
    ).outcome,
    'retry',
  );
});

test('a refused host or unusable keys are gone without any request', async () => {
  const { vapid } = await newVapid();
  const calls = [];
  const fetchImpl = pushFetch(201, calls);
  const good = await newSubscription();

  const wrongHost = await sendWebPush({
    fetchImpl,
    vapid,
    subscription: { ...good, endpoint: 'https://evil.example/x' },
    payload: {},
    nowMs: 0,
  });
  const badKeys = await sendWebPush({
    fetchImpl,
    vapid,
    subscription: { ...good, auth: 'AAAA' },
    payload: {},
    nowMs: 0,
  });
  assert.equal(wrongHost.outcome, 'gone');
  assert.equal(badKeys.outcome, 'gone');
  assert.equal(calls.length, 0);
});

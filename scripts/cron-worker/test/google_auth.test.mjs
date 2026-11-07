import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';

import {
  signServiceAccountJwt,
  mintCustomToken,
  getAccessToken,
  clearTokenCacheForTests,
  SCOPE,
  TOKEN_URL,
} from '../src/google_auth.mjs';

function base64UrlDecode(str) {
  const padded = str + '='.repeat((4 - (str.length % 4)) % 4);
  return Buffer.from(padded.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function makeServiceAccount() {
  const { publicKey, privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  return {
    publicKey,
    serviceAccount: {
      client_email: 'cron-worker-test@example.iam.gserviceaccount.com',
      private_key: privateKey,
    },
  };
}

test('signs a JWT with the right header, claims, and a verifiable RS256 signature', async () => {
  const { publicKey, serviceAccount } = makeServiceAccount();
  const nowSeconds = 1_700_000_000;
  const { jwt, claims } = await signServiceAccountJwt(serviceAccount, { nowSeconds });

  const [headerPart, payloadPart, signaturePart] = jwt.split('.');
  const header = JSON.parse(base64UrlDecode(headerPart).toString('utf8'));
  const payload = JSON.parse(base64UrlDecode(payloadPart).toString('utf8'));

  assert.deepEqual(header, { alg: 'RS256', typ: 'JWT' });
  assert.equal(payload.iss, serviceAccount.client_email);
  assert.equal(payload.scope, SCOPE);
  assert.equal(payload.aud, TOKEN_URL);

  assert.equal(payload.iat, nowSeconds - 30);
  assert.equal(payload.exp, nowSeconds + 3600);
  assert.deepEqual(payload, claims);

  const verifier = createVerify('RSA-SHA256');
  verifier.update(`${headerPart}.${payloadPart}`);
  assert.equal(verifier.verify(publicKey, base64UrlDecode(signaturePart)), true);
});

test('a tampered claim fails signature verification', async () => {
  const { publicKey, serviceAccount } = makeServiceAccount();
  const { jwt } = await signServiceAccountJwt(serviceAccount, { nowSeconds: 1_700_000_000 });
  const [headerPart, , signaturePart] = jwt.split('.');
  const tamperedPayload = Buffer.from(JSON.stringify({ iss: 'someone-else', scope: SCOPE }))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const verifier = createVerify('RSA-SHA256');
  verifier.update(`${headerPart}.${tamperedPayload}`);
  assert.equal(verifier.verify(publicKey, base64UrlDecode(signaturePart)), false);
});

test('getAccessToken exchanges the JWT and caches the token in-process', async () => {
  clearTokenCacheForTests();
  const { serviceAccount } = makeServiceAccount();
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return new Response(JSON.stringify({ access_token: 'token-1', expires_in: 3600 }), { status: 200 });
  };

  const token1 = await getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_000_000 });
  const token2 = await getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_000_010 });

  assert.equal(token1, 'token-1');
  assert.equal(token2, 'token-1');
  assert.equal(calls.length, 1, 'a cached token must not re-mint');
  assert.equal(calls[0].url, TOKEN_URL);
});

test('getAccessToken re-mints once the cached token is near expiry', async () => {
  clearTokenCacheForTests();
  const { serviceAccount } = makeServiceAccount();
  let call = 0;
  const fetchImpl = async () => {
    call += 1;
    return new Response(
      JSON.stringify({ access_token: `token-${call}`, expires_in: 3600 }),
      { status: 200 },
    );
  };

  const first = await getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_000_000 });
  const second = await getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_003_600 });

  assert.equal(first, 'token-1');
  assert.equal(second, 'token-2');
  assert.equal(call, 2);
});

test('concurrent calls for the same service account coalesce onto one mint', async () => {
  clearTokenCacheForTests();
  const { serviceAccount } = makeServiceAccount();
  let call = 0;
  const fetchImpl = async () => {
    call += 1;

    await new Promise((resolve) => setTimeout(resolve, 10));
    return new Response(
      JSON.stringify({ access_token: `token-${call}`, expires_in: 3600 }),
      { status: 200 },
    );
  };

  const [first, second] = await Promise.all([
    getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_000_000 }),
    getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_000_000 }),
  ]);

  assert.equal(first, second);
  assert.equal(call, 1, 'two concurrent calls must mint only one token');
});

test('a hanging token exchange aborts after the request timeout instead of hanging the run', async () => {
  clearTokenCacheForTests();
  const { serviceAccount } = makeServiceAccount();

  mock.timers.enable({ apis: ['setTimeout'] });
  try {
    let fetchCalled;
    const called = new Promise((resolve) => {
      fetchCalled = resolve;
    });
    const fetchImpl = (url, init) => {
      fetchCalled();
      return new Promise((resolve, reject) => {
        init.signal.addEventListener('abort', () => reject(new Error('aborted')));
      });
    };
    const pending = getAccessToken(serviceAccount, { fetchImpl, nowSeconds: 1_700_000_000 });
    const assertion = assert.rejects(pending);
    await called;
    mock.timers.tick(10_000);
    await assertion;
  } finally {
    mock.timers.reset();
  }
});

test('mintCustomToken signs a Firebase Auth custom token for the given uid, distinct from the OAuth JWT', async () => {
  const { publicKey, serviceAccount } = makeServiceAccount();
  const nowSeconds = 1_700_000_000;
  const jwt = await mintCustomToken(serviceAccount, 'canary-uid', { nowSeconds });

  const [headerPart, payloadPart, signaturePart] = jwt.split('.');
  const header = JSON.parse(base64UrlDecode(headerPart).toString('utf8'));
  const payload = JSON.parse(base64UrlDecode(payloadPart).toString('utf8'));

  assert.deepEqual(header, { alg: 'RS256', typ: 'JWT' });
  assert.equal(payload.iss, serviceAccount.client_email);
  assert.equal(payload.sub, serviceAccount.client_email);
  assert.equal(payload.uid, 'canary-uid');

  assert.notEqual(payload.aud, TOKEN_URL);
  assert.match(payload.aud, /identitytoolkit/);
  assert.equal(payload.iat, nowSeconds - 30);

  assert.equal(payload.exp, payload.iat + 3600);
  assert.equal(payload.exp, nowSeconds + 3570);
  assert.equal(payload.exp - payload.iat, 3600);

  const verifier = createVerify('RSA-SHA256');
  verifier.update(`${headerPart}.${payloadPart}`);
  assert.equal(verifier.verify(publicKey, base64UrlDecode(signaturePart)), true);
});

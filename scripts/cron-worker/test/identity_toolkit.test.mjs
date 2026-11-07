import { test } from 'node:test';
import assert from 'node:assert/strict';

import { signInWithCustomToken, IdentityToolkitError } from '../src/identity_toolkit.mjs';

test('signInWithCustomToken posts the token to the right endpoint and returns the id token', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url: String(url), init });
    return new Response(
      JSON.stringify({ idToken: 'id-token-1', localId: 'canary-uid' }),
      { status: 200 },
    );
  };

  const result = await signInWithCustomToken(fetchImpl, 'web-api-key', 'custom-token-1');

  assert.equal(result.idToken, 'id-token-1');
  assert.equal(result.localId, 'canary-uid');
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /^https:\/\/identitytoolkit\.googleapis\.com\/v1\/accounts:signInWithCustomToken\?key=web-api-key$/);
  const body = JSON.parse(calls[0].init.body);
  assert.deepEqual(body, { token: 'custom-token-1', returnSecureToken: true });
});

test('a non-2xx response throws IdentityToolkitError carrying the status', async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ error: { message: 'INVALID_CUSTOM_TOKEN' } }), { status: 400 });

  await assert.rejects(
    signInWithCustomToken(fetchImpl, 'web-api-key', 'bad-token'),
    (err) => {
      assert.ok(err instanceof IdentityToolkitError);
      assert.equal(err.status, 400);
      return true;
    },
  );
});

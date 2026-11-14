import { test } from 'node:test';
import assert from 'node:assert/strict';

import { filterIceServers, iceServers, STUN_ONLY } from '../src/chat_ice.mjs';

const TURN_ENV = { TURN_KEY_ID: 'key-1', TURN_KEY_API_TOKEN: 'secret-token' };

const cloudflareList = {
  iceServers: [
    {
      urls: [
        'stun:stun.cloudflare.com:3478',
        'stun:stun.cloudflare.com:53',
        'turn:turn.cloudflare.com:3478?transport=udp',
        'turn:turn.cloudflare.com:53?transport=udp',
        'turn:turn.cloudflare.com:80?transport=tcp',
        'turns:turn.cloudflare.com:5349?transport=tcp',
        'turns:turn.cloudflare.com:443?transport=tcp',
      ],
      username: 'user',
      credential: 'pass',
    },
  ],
};

test('without the TURN secrets the list is STUN only and nothing is fetched', async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
  };
  assert.deepEqual(await iceServers({}, fetchImpl), STUN_ONLY);
  assert.deepEqual(await iceServers({ TURN_KEY_ID: 'only-one' }, fetchImpl), STUN_ONLY);
  assert.equal(calls, 0);
  assert.deepEqual(
    STUN_ONLY.flatMap((s) => s.urls),
    ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'],
  );
});

test('with the secrets it asks Cloudflare for a one hour credential', async () => {
  let seen;
  const fetchImpl = async (url, init) => {
    seen = { url, init };
    return new Response(JSON.stringify(cloudflareList), { status: 200 });
  };
  await iceServers(TURN_ENV, fetchImpl);
  assert.equal(
    seen.url,
    'https://rtc.live.cloudflare.com/v1/turn/keys/key-1/credentials/generate-ice-servers',
  );
  assert.equal(seen.init.method, 'POST');
  assert.equal(seen.init.headers.Authorization, 'Bearer secret-token');
  assert.deepEqual(JSON.parse(seen.init.body), { ttl: 3600 });
});

test('URLs on port 53 are dropped and the credential stays on the rest', async () => {
  const fetchImpl = async () => new Response(JSON.stringify(cloudflareList), { status: 200 });
  const [server] = await iceServers(TURN_ENV, fetchImpl);
  assert.deepEqual(server.urls, [
    'stun:stun.cloudflare.com:3478',
    'turn:turn.cloudflare.com:3478?transport=udp',
    'turn:turn.cloudflare.com:80?transport=tcp',
    'turns:turn.cloudflare.com:5349?transport=tcp',
    'turns:turn.cloudflare.com:443?transport=tcp',
  ]);
  assert.equal(server.username, 'user');
  assert.equal(server.credential, 'pass');
});

test('a server left with no URL is removed, and port 530 is not port 53', () => {
  const kept = filterIceServers([
    { urls: ['turn:a.example:53'] },
    { urls: 'turn:b.example:53?transport=udp' },
    { urls: ['turn:c.example:530'] },
    { urls: ['stun:d.example'] },
    { urls: ['stun:[2001:db8::1]:53'] },
    null,
  ]);
  assert.deepEqual(
    kept.flatMap((s) => s.urls),
    ['turn:c.example:530', 'stun:d.example'],
  );
  assert.deepEqual(filterIceServers(undefined), []);
});

test('a TURN failure falls back to STUN only', async () => {
  const quiet = console.error;
  console.error = () => {};
  try {
    const refused = async () => new Response('nope', { status: 403 });
    assert.deepEqual(await iceServers(TURN_ENV, refused), STUN_ONLY);
    const thrown = async () => {
      throw new Error('network down');
    };
    assert.deepEqual(await iceServers(TURN_ENV, thrown), STUN_ONLY);
    const empty = async () => new Response(JSON.stringify({ iceServers: [] }), { status: 200 });
    assert.deepEqual(await iceServers(TURN_ENV, empty), STUN_ONLY);
    const garbage = async () => new Response('not json', { status: 200 });
    assert.deepEqual(await iceServers(TURN_ENV, garbage), STUN_ONLY);
  } finally {
    console.error = quiet;
  }
});
